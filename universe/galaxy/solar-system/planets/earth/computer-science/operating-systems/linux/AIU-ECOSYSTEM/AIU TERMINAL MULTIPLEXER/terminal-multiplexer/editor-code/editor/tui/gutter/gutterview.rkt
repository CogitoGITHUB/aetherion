#lang racket/base
(require racket/string
         "../blocks/blockview.rkt"
         "gutter.rkt"
         "../../commands/commands.rkt"
         "../../bridge/host.rkt"
         "../../bridge/document.rkt")

(define (mark-of hunks lo hi)
  (define hit
    (filter (lambda (h)
              (and (<= (car h) hi) (>= (cadr h) lo)
                   (or (not (string=? (caddr h) "-"))
                       (and (>= (car h) lo) (< (car h) hi)))))
            hunks))
  (cond [(null? hit) #f]
        [(and (null? (cdr hit)) (not (string=? (caddr (car hit)) "-"))) (caddr (car hit))]
        [else "="]))

(define (leaf? blocks b)
  (not (for/or ([c (in-list blocks)])
         (and (not (eq? c b))
              (not (string=? (block-name c) "answer"))
              (> (block-start c) (block-start b))
              (<= (block-end c) (block-end b))))))

(define (gutter-apply session text)
  (define lines (string-split text "\n" #:trim? #f))
  (define hunks (gutter-hunks (session-file session)))
  (define got (page-of (session-file session) (session-journal session)))
  (define marks (make-hash))
  (when (and (pair? hunks) (page? got))
    (define blocks (page-blocks got))
    (define ranges (blockview-ranges got lines))
    (define drawn
      (sort (filter (lambda (b) (and (leaf? blocks b) (hash-ref ranges (block-start b) #f))) blocks)
            < #:key block-start-line))
    (for ([b (in-list drawn)])
      (define m (mark-of hunks (block-start-line b) (block-end-line b)))
      (define r (hash-ref ranges (block-start b)))
      (when m
        (for ([i (in-range (car r) (add1 (cdr r)))]) (hash-set! marks i m))))
    (for ([h (in-list hunks)] #:when (string=? (caddr h) "-"))
      (define at (car h))
      (unless (for/or ([b (in-list drawn)])
                (and (>= at (block-start-line b)) (< at (block-end-line b))))
        (define after (filter (lambda (b) (> (block-start-line b) at)) drawn))
        (define target (if (pair? after) (car after) (and (pair? drawn) (car (reverse drawn)))))
        (when target
          (define i (car (hash-ref ranges (block-start target))))
          (unless (hash-ref marks i #f) (hash-set! marks i "-"))))))
  (string-join
   (for/list ([l (in-list lines)] [i (in-naturals)])
     (string-append (hash-ref marks i " ") l))
   "\n"))

(provide gutter-apply)
