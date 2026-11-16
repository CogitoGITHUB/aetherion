#lang racket/base

(require racket/list
         racket/path racket/port
         racket/path racket/port
         racket/string
         "../../narration/print-console-shared.rkt"
         "../../commands/commands-shared.rkt"
         "../../join/hot-path-shared.rkt"
         "../../join/live-wire-shared.rkt"
         "../../join/protocol-shared.rkt"
         "../../drawing/screen.rkt"
         "../../machine/terminal.rkt"
         "../../routes/keyboard.rkt"
         "../../routes/keymaps-shared.rkt"
         "../../routes/routes.rkt"
         "../../bridge/document-shared.rkt"
         "../../bridge/host-shared.rkt"
         "../../bridge/where-shared.rkt"
         "../../tui/blocks/blockview.rkt" "../../tui/blocks/blocks-edit.rkt" "../../tui/blocks/blocks-view.rkt"
         "../../tui/blocks/blocks-move.rkt"
         "../../tui/bar/bar-menu-shared.rkt"
         "../../tui/bar/bar.rkt" (only-in "../../tui/bar/bar-state-shared.rkt" name-prompt)
         "../../tui/tabs/tabs-shared.rkt"
         "../../tui/tabs/finder.rkt"
         "../../tui/keys/key-notes.rkt" (only-in "../../tui/notify/notify.rkt" notify!)
         (only-in "../../tui/float/box-shared.rkt" paint-ready)
         "../../tui/gutter/gutter.rkt"
         "../../tui/gutter/gutterview.rkt"
         (only-in "../../machine/directories-shared.rkt" journal-path-for))
(require "live-paint.rkt")

(provide key-loop trace-session!)

(struct outcome (rest go-on?) #:transparent)

(define (read-available port chunk)
  (define n (read-bytes-avail! chunk port))
  (cond
    [(eof-object? n) 'eof]
    [(zero? n) '()]
    [else (for/list ([i (in-range n)]) (bytes-ref chunk i))]))

(define in-paste (box #f))
(define paste-hit (box #f))
(define paste-shown (box #f))
(define paste-begin (list 27 91 50 48 48 126))
(define paste-end (list 27 91 50 48 49 126))

(define (starts? l p)
  (and (>= (length l) (length p)) (equal? (take l (length p)) p)))

(define (strip-paste l)
  (let loop ([l l] [out (list)])
    (cond
      [(null? l) (reverse out)]
      [(unbox in-paste)
       (if (starts? l paste-end)
           (begin (set-box! in-paste #f) (loop (list-tail l 6) out))
           (loop (cdr l) out))]
      [(starts? l paste-begin)
       (set-box! in-paste #t)
       (set-box! paste-hit #t)
       (loop (list-tail l 6) out)]
      [else (loop (cdr l) (cons (car l) out))])))

(define (drop-paste session got)
  (cond
    [(not (list? got)) got]
    [(or (not (string=? (the-layer session) "write"))
         (and (regexp-match? #rx"[.]aiu$" (path->string (session-file session)))
              (unbox read-mode)))
     (let ([r (strip-paste got)])
       (when (unbox paste-hit)
         (set-box! paste-hit #f)
         (set-box! paste-shown #t)
         (notify! "warn" "paste ignored: not in writing mode"))
       r)]
    [else (set-box! in-paste #f) got]))

(define (emit-tabs!)
  (when (getenv "AIU_IN_MULTIPLEXER")
    (write-string (tab-osc) (current-output-port))
    (flush-output (current-output-port))))

(define (key-loop session port viewport)
  (define chunk (make-bytes 1024))
  (emit-tabs!)
  (let loop ([buffer '()])
    (define arrived (drop-paste session (read-available port chunk)))
    (when (unbox paste-shown) (set-box! paste-shown #f) (begin (repaint session viewport) (emit-tabs!)))
    (unless (eq? arrived 'eof)
      (let walk ([pending (append buffer arrived)])
        (cond
          [(null? pending) (loop '())]
          [else
           (define trace-t0 (current-inexact-milliseconds))
           (define result (act-on session pending))
           (trace-key! pending trace-t0 result session)
             (set-box! pending-keys (if (eq? (outcome-rest result) (quote wait)) (map car (key-runs pending)) (list)))
           (unless (and (outcome-go-on? result) (or (pair? (outcome-rest result)) (sync/timeout 0 port)))
             (repaint session viewport) (emit-tabs!))
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
       [(and (string=? nm "") (not (member label (list "project" "workspace" "buffer")))) (set-box! name-prompt (list label buf cb "type a name first")) #t]
       [(and (not (equal? label "capture")) (regexp-match? #rx"[/]|^[.]" nm)) (set-box! name-prompt (list label buf cb "no slash and no leading dot")) #t]
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
