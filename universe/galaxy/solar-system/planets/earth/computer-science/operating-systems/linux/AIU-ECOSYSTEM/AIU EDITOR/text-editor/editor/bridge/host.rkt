#lang racket/base

(require racket/path
         racket/string
         "../join/hot-path.rkt"
         "../join/protocol.rkt"
         "document.rkt")

(struct page-refusal (text) #:transparent)

(define (answer-data answer name)
  (hash-ref (response-data answer) name ""))

(define (page-of file journal)
  (define answer
    (ask-hot "notation" (hasheq 'file (path->string file)
                                'journal (path->string journal))))
  (cond
    [(response-ok answer)
     (define got (read-page (answer-data answer 'document)))
     (if (page? got)
         got
         (page-refusal (format "the page cannot be read: ~a" got)))]
    [else
     (page-refusal (format "~a: ~a — ~a"
                      (answer-data answer 'kind)
                      (answer-data answer 'what)
                      (answer-data answer 'what_to_do)))]))

(define (render-of file journal)
  (define answer
    (ask-hot "notation-render" (hasheq 'file (path->string file)
                                       'journal (path->string journal))))
  (if (response-ok answer)
      (answer-data answer 'text)
      (format "~a: ~a — ~a"
              (answer-data answer 'kind)
              (answer-data answer 'what)
              (answer-data answer 'what_to_do))))

(define (page-answer? answer)
  (page? answer))

(define (view-of file journal width)
  (define answer
    (ask-hot "notation-view" (hasheq 'file (path->string file)
                                     'journal (path->string journal)
                                     'width (number->string width))))
  (if (response-ok answer)
      (hash-ref (response-data answer) 'text "")
      (format "~a: ~a — ~a"
              (answer-data answer 'kind)
              (answer-data answer 'what)
              (answer-data answer 'what_to_do))))

(provide page-refusal
         page-refusal-text
         page-of
         render-of
         view-of
         page-answer?)
