#lang racket/base
(require racket/list racket/string racket/path
         "bar-rows-shared.rkt" "bar-state-shared.rkt" "bar-git-shared.rkt" "../tabs/tabs-shared.rkt" "../float/box-shared.rkt")

(define git-asked 0)

(define (git-fresh)
  (when (>= (- (current-seconds) git-asked) 5)
    (set! git-asked (current-seconds))
    (let ([row (with-handlers ([(lambda (e) #t) (lambda (e) "git unavailable")])
                 (git-facts (path->string (current-directory))))])
      (set-box! git-info row)
      (set-box! tab-git-text (git-text row)))))

(define (bar-stack layer short width pending)
  (git-fresh)
  (define names (take bar-order (min (length bar-order) (max 0 (unbox bar-count)))))
  (define bars (bar-rows layer short pending (unbox git-info) width names))
  (define tabs (tab-rows (path->string (path->complete-path short)) width void))
  (if (and (pair? tabs) (pair? bars) (unbox tab-joined))
      (append (drop-right tabs 1) (list (join-edge (car bars))) (cdr bars))
      (append tabs bars)))

(define (serve)
  (define line (read-line))
  (unless (eof-object? line)
    (define parts (string-split line "\t" #:trim? #f))
    (define rows
      (with-handlers ([exn:fail? (lambda (why) (list (string-append "RACKET-ERROR " (car (string-split (exn-message why) "\n")))))])
        (begin (set-box! menu-pinned (and (> (length parts) 4) (string=? (list-ref parts 4) "1"))) (bar-stack (list-ref parts 0) (list-ref parts 1) (string->number (list-ref parts 2)) (if (> (length parts) 3) (string-split (list-ref parts 3) " ") null)))))
    (for ([row (in-list rows)])
      (displayln row))
    (displayln "")
    (flush-output)
    (serve)))

(module+ main (serve))
