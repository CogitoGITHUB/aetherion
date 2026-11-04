#lang racket/base
(require racket/list racket/string racket/path
         "bar-rows.rkt" "bar-state.rkt" "../tabs/tabs.rkt" "../float/box.rkt")

(define (bar-stack layer short width)
  (define names (take bar-order (min (length bar-order) (max 0 (unbox bar-count)))))
  (define bars (bar-rows layer short null #f width names))
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
        (bar-stack (list-ref parts 0) (list-ref parts 1) (string->number (list-ref parts 2)))))
    (for ([row (in-list rows)])
      (displayln row))
    (displayln "")
    (flush-output)
    (serve)))

(module+ main (serve))
