#lang racket/base
(require racket/file racket/string
         "../../commands/commands-shared.rkt"
         (only-in "../bar/bar-state-shared.rkt" name-prompt)
         "float-state-shared.rkt")

(provide)

(define (float-hide session)
  (set-box! float-visible #f)
  (set-layer! session "visual")
  (cons #t "float hidden"))

(define (float-open name)
  (define index
    (for/first ([n (in-list float-names)] [i (in-naturals)] #:when (string=? n name)) i))
  (cond
    [(and (unbox float-visible) (= (unbox float-active) index)) (set-box! float-visible #f)]
    [else
     (set-box! float-active index)
     (set-box! float-visible #t)])
  (cons #t ""))

(define (float-enter session)
  (set-box! float-visible #t)
  (set-layer! session "float")
  (cons #t "layer: float"))

(define (float-resize! change)
  (set-box! float-share (change (unbox float-share)))
  (cons #t ""))

(define (todo-line-append! text)
  (define path (float-file-path "todo" (float-root)))
  (define body (file->string path))
  (define ends (regexp-match-positions* #rx"section end" body))
  (define paragraph (string-append "paragraph start\ntodo: " text "\nPlanned.\nparagraph end\n\n"))
  (define at (if (null? ends) (string-length body) (car (car (reverse ends)))))
  (display-to-file (string-append (substring body 0 at) paragraph (substring body at)) path #:exists (quote replace)))

(define (float-capture session)
  (set-box! name-prompt
            (list "capture"
                  ""
                  (lambda (text)
                    (todo-line-append! text)
                    (cons #t "captured"))
                  ""))
  (cons #t "capture: type a line, return saves"))

(hash-set! commands "float-mode" (lambda (session words) (float-enter session)))
(hash-set! commands "float-todo" (lambda (session words) (float-open "todo")))
(hash-set! commands "float-journal" (lambda (session words) (float-open "journal")))
(hash-set! commands "float-notes" (lambda (session words) (float-open "notes")))
(hash-set! commands "float-back" (lambda (session words) (float-hide session)))
(hash-set! commands "float-size" (lambda (session words) (float-resize! float-next-share)))
(hash-set! commands "float-grow" (lambda (session words) (float-resize! float-grow-share)))
(hash-set! commands "float-shrink" (lambda (session words) (float-resize! float-shrink-share)))
(hash-set! commands "float-capture" (lambda (session words) (float-capture session)))
