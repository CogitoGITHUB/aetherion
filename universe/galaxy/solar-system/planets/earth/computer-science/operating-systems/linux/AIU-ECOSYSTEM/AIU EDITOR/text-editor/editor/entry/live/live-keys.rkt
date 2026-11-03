#lang racket/base

(require racket/list
         racket/path racket/port
         racket/path racket/port
         racket/string
         "../../narration/print-console.rkt"
         "../../commands/commands.rkt"
         "../../join/hot-path.rkt"
         "../../join/live-wire.rkt"
         "../../join/protocol.rkt"
         "../../drawing/screen.rkt"
         "../../machine/terminal.rkt"
         "../../routes/keyboard.rkt"
         "../../routes/keymaps.rkt"
         "../../routes/routes.rkt"
         "../../notation/document.rkt"
         "../../notation/host.rkt"
         "../../notation/where.rkt"
         "../../tui/blocks/blockview.rkt" "../../tui/blocks/blocks-edit.rkt" "../../tui/blocks/blocks-view.rkt"
         "../../tui/blocks/blocks-move.rkt"
         "../../tui/bar/bar-menu.rkt"
         "../../tui/bar/bar.rkt" (only-in "../../tui/bar/bar-state.rkt" name-prompt)
         "../../tui/tabs/tabs.rkt"
         "../../tui/tabs/finder.rkt"
         "../../tui/keys/key-notes.rkt"
         (only-in "../../tui/float/box.rkt" paint-ready)
         "../../tui/gutter/gutter.rkt"
         "../../tui/gutter/gutterview.rkt"
         (only-in "../../machine/directories.rkt" journal-path-for))
(require "live-paint.rkt")

(provide key-loop trace-session!)

(struct outcome (rest go-on?) #:transparent)

(define (read-available port chunk)
  (define n (read-bytes-avail! chunk port))
  (cond
    [(eof-object? n) 'eof]
    [(zero? n) '()]
    [else (for/list ([i (in-range n)]) (bytes-ref chunk i))]))

(define (key-loop session port viewport)
  (define chunk (make-bytes 1024))
  (let loop ([buffer '()])
    (define arrived (read-available port chunk))
    (unless (eq? arrived 'eof)
      (let walk ([pending (append buffer arrived)])
        (cond
          [(null? pending) (loop '())]
          [else
           (define trace-t0 (current-inexact-milliseconds))
           (define result (act-on session pending))
           (trace-key! pending trace-t0 result session)
             (set-box! pending-keys (if (eq? (outcome-rest result) (quote wait)) (map car (key-runs pending)) (list)))
           (repaint session viewport)
           (cond
             [(eq? (outcome-rest result) 'wait)
              (loop pending)]
             [(outcome-go-on? result)
              (walk (outcome-rest result))]
             [else (void)])])))))

(define (trace-session! file)
  (when (getenv "AIU_TRACE")
    (with-handlers ([void void])
      (call-with-output-file (or (let ([f (getenv "AIU_TRACE_FILE")]) (and f (string->path f))) (build-path (find-system-path (quote home-dir)) ".aiu-trace.log")) #:exists (quote append)
        (lambda (o) (fprintf o "~a session file ~a\n" (current-inexact-milliseconds) file))))))

(define (trace-key! pending t0 result session)
  (when (getenv "AIU_TRACE")
    (with-handlers ([void void])
      (call-with-output-file (or (let ([f (getenv "AIU_TRACE_FILE")]) (and f (string->path f))) (build-path (find-system-path (quote home-dir)) ".aiu-trace.log")) #:exists (quote append)
        (lambda (o)
          (fprintf o "~a act-on ~a ms pending ~s go-on ~a layer ~a rest ~a\n" (current-inexact-milliseconds) (- (current-inexact-milliseconds) t0) (if (> (length pending) 3) (take pending 3) pending) (outcome-go-on? result) (the-layer session) (let ([r (outcome-rest result)]) (if (list? r) (length r) r))))))))

(define (longest-binding layer names)
  (let loop ([k (length names)])
    (cond
      [(zero? k) 0]
      [(binding-of layer (string-join (take names k) " ")) k]
      [else (loop (sub1 k))])))

(define (act-on session buffer)
  (if (unbox name-prompt) (act-prompt session buffer) (act-on-file session buffer)))

(define (act-on-file session buffer)
  (define runs (key-runs buffer))
  (cond
    [(null? runs)
     (outcome 'wait #t)]
    [else
     (define names (map car runs))
     (define layer (the-layer session))
     (define matched (longest-binding layer names))
     (cond
       [(> matched 0)
        (outcome (drop-bytes buffer (take runs matched))
                 (run-it session (binding-of layer (string-join (take names matched) " "))))]
       [(prefix-of? layer names)
        (outcome 'wait #t)]
       [(and (not (string=? layer "write")) (text-of (car names)))
        (key-note-none names (mode-label layer))
        (outcome (drop-bytes buffer (list (car runs))) #t)]
       [(text-of (car names))
        (outcome (drop-bytes buffer (list (car runs)))
                 (run-it-words session "type" (list (text-of (car names)))))]
       [else
        (key-note-none names (mode-label layer))
        (outcome (drop-bytes buffer (list (car runs))) #t)])]))

(define (run-it session line)
  (block-guard session line (lambda () (run-it-file session line))))

(define (run-it-file session line)
  (car (run-command session line)))

(define (run-it-words session name words)
  (run-it-words-file session name words))

(define (run-it-words-file session name words)
  (car (run-command-words session name words)))

(define (drop-bytes buffer runs)
  (define taken (for/sum ([run (in-list runs)]) (cdr run)))
  (if (>= taken (length buffer))
      '()
      (drop buffer taken)))

(define (prompt-step! name)
  (define p (unbox name-prompt))
  (define label (car p))
  (define buf (cadr p))
  (define cb (caddr p))
  (cond
    [(equal? name "escape") (set-box! name-prompt #f) #t]
    [(equal? name "backspace")
     (set-box! name-prompt (list label (if (string=? buf "") buf (substring buf 0 (sub1 (string-length buf)))) cb ""))
     #t]
    [(equal? name "return")
     (define nm (string-trim buf))
     (cond
       [(string=? nm "") (set-box! name-prompt (list label buf cb "type a name first")) #t]
       [(regexp-match? #rx"[/]|^[.]" nm) (set-box! name-prompt (list label buf cb "no slash and no leading dot")) #t]
       [else
        (define r (cb nm))
        (cond
          [(car r) (set-box! name-prompt (list label buf cb (cdr r))) #t]
          [else (set-box! name-prompt #f) #f])])]
    [(text-of name)
     (set-box! name-prompt (list label (string-append buf (text-of name)) cb ""))
     #t]
    [else #t]))

(define (act-prompt session buffer)
  (define runs (key-runs buffer))
  (cond
    [(null? runs) (outcome (quote wait) #t)]
    [else
     (define go
       (for/fold ([go #t]) ([r (in-list runs)])
         (if (and go (unbox name-prompt)) (prompt-step! (car r)) go)))
     (outcome (drop-bytes buffer runs) go)]))
