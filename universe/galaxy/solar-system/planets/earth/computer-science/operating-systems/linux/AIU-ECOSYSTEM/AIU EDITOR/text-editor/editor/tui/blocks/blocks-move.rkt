#lang racket/base
(require racket/list racket/string "../../commands/commands.rkt" "../../machine/terminal.rkt" "../../notation/document.rkt" "../../notation/host.rkt" "blockview.rkt")

(define (blockview-siblings blocks b)
  (define parent (blockview-parent blocks b))
  (sort (filter (lambda (k)
                  (and (= (block-depth k) (block-depth b))
                       (not (member (block-name k) (list "answer" "title")))
                       (equal? (blockview-parent blocks k) parent)))
                blocks)
        < #:key block-start))

(define (blockview-move session direction)
  (define got (and (blockview-aiu? session)
                   (page-of (session-file session) (session-journal session))))
  (cond
    [(not (page? got)) (cons #t "block move needs a page of the notation")]
    [else
     (define bs (string->bytes/utf-8 (session-text session)))
     (define cur (blockview-inside (blockview-drawn (page-blocks got)) (the-point session)))
     (define sibs (if cur (blockview-siblings (page-blocks got) cur) null))
     (define idx
       (for/first ([k (in-list sibs)] [n (in-naturals)]
                   #:when (= (block-start k) (block-start cur)))
         n))
     (define other-idx (and idx (+ idx direction)))
     (cond
       [(not idx) (cons #t "no block can move here")]
       [(or (< other-idx 0) (>= other-idx (length sibs)))
        (cons #t "no block there to swap with")]
       [else
        (define other (list-ref sibs other-idx))
        (define a (if (< direction 0) other cur))
        (define b (if (< direction 0) cur other))
        (define a0 (block-start a))
        (define a1 (min (block-end a) (bytes-length bs)))
        (define b0 (block-start b))
        (define b1 (min (block-end b) (bytes-length bs)))
        (define (piece lo hi) (bytes->string/utf-8 (subbytes bs lo hi) #\?))
        (ask session "delete-at"
             (hasheq (quote at) (number->string a0) (quote count) (number->string (- b1 a0))))
        (ask session "insert-at"
             (hasheq (quote at) (number->string a0)
                     (quote text) (string-append (piece b0 b1) (piece a1 b0) (piece a0 a1))))
        (move-to session (if (< direction 0) a0 (+ a0 (- b1 a1))))
        (cons #t (format "moved the ~a block ~a" (block-name cur) (if (< direction 0) "up" "down")))])]))

(define (blockview-command-move-up session words)
  (blockview-move session -1))

(define (blockview-command-move-down session words)
  (blockview-move session 1))

(define (blockview-command-move-mode session words)
  (set-layer! session "move")
  (cons #t "layer: move"))


(hash-set! commands "block-move-up" blockview-command-move-up)
(hash-set! commands "block-move-down" blockview-command-move-down)
(hash-set! commands "block-move-mode" blockview-command-move-mode)
