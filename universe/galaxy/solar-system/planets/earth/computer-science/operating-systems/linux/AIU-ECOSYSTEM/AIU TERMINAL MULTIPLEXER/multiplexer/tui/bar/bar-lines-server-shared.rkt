#lang racket/base
(require racket/list racket/string racket/path
         "bar-rows-shared.rkt" "bar-state-shared.rkt" "bar-git-shared.rkt" "../tabs/tabs-shared.rkt" "../float/box-shared.rkt")

(define git-running (box #f))
(define last-layer (box #f))

(define (git-refresh-in-background)
  (unless (unbox git-running)
    (set-box! git-running #t)
    (thread
     (lambda ()
       (let ([row (with-handlers ([(lambda (e) #t) (lambda (e) "git unavailable")])
                    (git-facts (path->string (current-directory))))])
         (set-box! git-info row)
         (set-box! tab-git-text (git-text row)))
       (set-box! git-running #f)))))

(define (git-on-layer layer)
  (unless (equal? layer (unbox last-layer))
    (set-box! last-layer layer)
    (when (string=? layer "visual") (git-refresh-in-background))))

(define (set-buffer-fields! parts)
  (when (and (> (length parts) 7) (not (string=? (list-ref parts 7) "")) (directory-exists? (list-ref parts 7)))
    (define wanted (path->directory-path (string->path (list-ref parts 7))))
    (unless (equal? wanted (path->directory-path (current-directory)))
      (current-directory wanted)
      (set-box! last-layer #f)))
  (when (> (length parts) 6)
    (set-box! tab-buffers (string-split (list-ref parts 5) "\u001f"))
    (set-box! tab-buffer-current (or (string->number (list-ref parts 6)) 0))))

(define (bar-stack layer short width pending)
  (git-on-layer layer)
  (define names (remove "keys" (take bar-order (min (length bar-order) (max 0 (unbox bar-count))))))
  (define bars (bar-rows layer short pending (unbox git-info) width names))
  (define tab-file (path->string (path->complete-path short)))
  (set-box! tab-files (list tab-file))
  (set-box! tab-current tab-file)
  (define tabs-plain (tab-rows tab-file width void))
  (define tabs
    (append (take tabs-plain 2)
            (if (null? (keys-body-rows layer pending width)) null (list (edge-line "├" "┤" "keys" "" width)))
            (keys-body-rows layer pending width)
            (drop tabs-plain 2)))
  tabs)

(define mux-nav (box (list "" "0" "" "0")))
(define (set-nav-field! parts)
  (when (> (length parts) 9)
    (define f (string-split (list-ref parts 9) "\u001d" #:trim? #f))
    (when (= (length f) 4) (set-box! mux-nav f))))
(define (mux-mark names at)
  (string-join
   (for/list ([n (in-list names)] [i (in-naturals)])
     (if (eqv? i at) (string-append "● " n) n))
   "   "))
(define (mux-boxes width)
  (define f (unbox mux-nav))
  (define (one title names idx)
    (define l
      (if (string=? names "")
          null
          (string-split names "\u001f" #:trim? #f)))
    (if (> (length l) 1)
        (list (cons title (mux-mark l (or (string->number idx) 0))))
        null))
  (append
   (one "workspace" (car f) (cadr f))
   (one "project" (caddr f) (cadddr f))
   (let ([bufs (unbox tab-buffers)])
     (if (> (length bufs) 1)
         (list (cons "buffer"
                     (mux-mark bufs (unbox tab-buffer-current))))
         null))))
(define (set-prompt-field! parts)  (set-box! name-prompt
            (if (and (> (length parts) 8) (not (string=? (list-ref parts 8) "")))
                (let ([p (string-split (list-ref parts 8) "\u001e" #:trim? #f)])
                  (list (car p) (if (pair? (cdr p)) (cadr p) "") #f ""))
                #f)))

(define (bar-stack-new layer short width pending)
  (git-on-layer layer)
  (define tab-file (path->string (path->complete-path short)))
  (set-box! tab-files (list tab-file))
  (set-box! tab-current tab-file)
  (define keys (keys-body-rows layer pending width))
  (define p (unbox name-prompt))
  (define boxes
    (append
     (for/list ([s (in-list (mux-boxes width))] #:when (or (equal? (car s) "buffer") (string-prefix? layer (car s))))
       (cons (car s) (list (body-line (cdr s) width))))
     (if p
         (list (cons "name" (list (body-line (format "~a: ~a▏" (car p) (cadr p)) width)
                                  (body-line "return creates   escape cancels" width))))
         (list))
     (if (null? keys) (list) (list (cons "keys" keys)))))
  (if (null? boxes)
      (list)
      (append
       (append* (for/list ([b (in-list boxes)] [i (in-naturals)])
                  (cons (edge-line (if (= i 0) "╭" "├") (if (= i 0) "╮" "┤") (car b) "" width) (cdr b))))
       (list (rule-line "╰" "╯" width)))))

(define (serve)
  (define line (read-line))
  (unless (eof-object? line)
    (define parts (string-split line "\t" #:trim? #f))
    (define rows
      (with-handlers ([exn:fail? (lambda (why) (list (string-append "RACKET-ERROR " (car (string-split (exn-message why) "\n")))))])
        (begin (set-buffer-fields! parts) (set-nav-field! parts) (set-prompt-field! parts) (set-box! menu-pinned (and (> (length parts) 4) (string=? (list-ref parts 4) "1"))) (bar-stack-new (list-ref parts 0) (list-ref parts 1) (string->number (list-ref parts 2)) (if (> (length parts) 3) (string-split (list-ref parts 3) " ") null)))))
    (for ([row (in-list rows)])
      (displayln row))
    (displayln "")
    (flush-output)
    (serve)))

(module+ main (serve))
