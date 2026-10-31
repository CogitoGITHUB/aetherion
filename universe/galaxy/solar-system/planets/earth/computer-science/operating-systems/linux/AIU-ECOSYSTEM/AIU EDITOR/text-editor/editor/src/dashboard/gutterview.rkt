#lang racket/base
;; gutterview.rkt: puts one column at the left of every line of a drawn page,
;; with the git mark of the block that line belongs to, or a space.
(require racket/string
         "blockview.rkt"
         "gutter.rkt"
         "../commands/commands.rkt"
         "../notation/host.rkt"
         "../notation/document.rkt")

;; mark-of answers the mark of the lines first to last: the mark of the one
;; hunk that touches them, equals when several do, or false when none.
(define (mark-of hunks lo hi)
  (define hit (filter (lambda (h) (and (<= (car h) hi) (>= (cadr h) lo))) hunks))
  (cond [(null? hit) #f]
        [(null? (cdr hit)) (caddr (car hit))]
        [else "="]))

;; leaf? answers whether no other drawn block sits inside this block.
(define (leaf? blocks b)
  (not (for/or ([c (in-list blocks)])
         (and (not (eq? c b))
              (not (string=? (block-name c) "answer"))
              (> (block-start c) (block-start b))
              (<= (block-end c) (block-end b))))))

;; gutter-apply answers the page text with the strip column at the left of
;; every line. The marks go on every drawn line of a leaf block that a hunk
;; touches.
(define (gutter-apply session text)
  (define lines (string-split text "\n" #:trim? #f))
  (define hunks (gutter-hunks (session-file session)))
  (define got (page-of (session-file session) (session-journal session)))
  (define marks (make-hash))
  (when (and (pair? hunks) (page? got))
    (define blocks (page-blocks got))
    (define ranges (bv-ranges got lines))
    (for ([b (in-list blocks)] #:when (leaf? blocks b))
      (define m (mark-of hunks (block-start-line b) (block-end-line b)))
      (define r (hash-ref ranges (block-start b) #f))
      (when (and m r)
        (for ([i (in-range (car r) (add1 (cdr r)))]) (hash-set! marks i m)))))
  (string-join
   (for/list ([l (in-list lines)] [i (in-naturals)])
     (string-append (hash-ref marks i " ") l))
   "\n"))

(provide gutter-apply)
