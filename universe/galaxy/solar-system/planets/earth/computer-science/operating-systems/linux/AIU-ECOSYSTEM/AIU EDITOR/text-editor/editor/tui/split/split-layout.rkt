#lang racket/base

(require racket/list)

(provide split-layout-single split-layout-split split-layout-close split-layout-ids split-layout-rects split-layout-neighbour split-layout-resize split-layout-swap split-layout-flip split-layout-turn split-layout-equalise)

(define (split-layout-single id) (list "pane" id))

(define (split-layout-pane? tree) (equal? (car tree) "pane"))

(define (split-layout-split tree focus-id new-id direction)
  (cond
    [(split-layout-pane? tree)
     (if (equal? (cadr tree) focus-id)
         (list "split" direction tree (list "pane" new-id) 50)
         tree)]
    [else
     (list "split" (cadr tree)
           (split-layout-split (caddr tree) focus-id new-id direction)
           (split-layout-split (cadddr tree) focus-id new-id direction)
           (list-ref tree 4))]))

(define (split-layout-close tree id)
  (cond
    [(split-layout-pane? tree) (if (equal? (cadr tree) id) #f tree)]
    [else
     (define first-tree (split-layout-close (caddr tree) id))
     (define second-tree (split-layout-close (cadddr tree) id))
     (cond
       [(not first-tree) second-tree]
       [(not second-tree) first-tree]
       [else (list "split" (cadr tree) first-tree second-tree (list-ref tree 4))])]))

(define (split-layout-ids tree)
  (if (split-layout-pane? tree)
      (list (cadr tree))
      (append (split-layout-ids (caddr tree)) (split-layout-ids (cadddr tree)))))

(define (split-layout-first-size size ratio)
  (max 1 (min (- size 1) (quotient (* size ratio) 100))))

(define (split-layout-rects tree left top width height)
  (cond
    [(split-layout-pane? tree) (list (list (cadr tree) left top width height))]
    [(equal? (cadr tree) "right")
     (define first-width (split-layout-first-size width (list-ref tree 4)))
     (append (split-layout-rects (caddr tree) left top first-width height)
             (split-layout-rects (cadddr tree) (+ left first-width) top (- width first-width) height))]
    [else
     (define first-height (split-layout-first-size height (list-ref tree 4)))
     (append (split-layout-rects (caddr tree) left top width first-height)
             (split-layout-rects (cadddr tree) left (+ top first-height) width (- height first-height)))]))

(define (split-layout-overlap start-a size-a start-b size-b)
  (and (< start-a (+ start-b size-b)) (> (+ start-a size-a) start-b)))

(define (split-layout-adjacent? here other direction)
  (define-values (here-left here-top here-width here-height) (values (cadr here) (caddr here) (cadddr here) (list-ref here 4)))
  (define-values (other-left other-top other-width other-height) (values (cadr other) (caddr other) (cadddr other) (list-ref other 4)))
  (cond
    [(equal? direction "left")
     (and (= (+ other-left other-width) here-left) (split-layout-overlap other-top other-height here-top here-height))]
    [(equal? direction "right")
     (and (= other-left (+ here-left here-width)) (split-layout-overlap other-top other-height here-top here-height))]
    [(equal? direction "up")
     (and (= (+ other-top other-height) here-top) (split-layout-overlap other-left other-width here-left here-width))]
    [else
     (and (= other-top (+ here-top here-height)) (split-layout-overlap other-left other-width here-left here-width))]))

(define (split-layout-distance here other direction)
  (if (member direction (list "left" "right"))
      (abs (- (+ (caddr here) (quotient (list-ref here 4) 2)) (+ (caddr other) (quotient (list-ref other 4) 2))))
      (abs (- (+ (cadr here) (quotient (cadddr here) 2)) (+ (cadr other) (quotient (cadddr other) 2))))))

(define (split-layout-neighbour tree id direction width height)
  (define rects (split-layout-rects tree 0 0 width height))
  (define here (assoc id rects))
  (define candidates
    (if here
        (filter (lambda (other) (split-layout-adjacent? here other direction)) rects)
        (list)))
  (if (null? candidates)
      #f
      (car (argmin (lambda (other) (split-layout-distance here other direction)) candidates))))

(define (split-layout-ratio-clamped ratio) (max 10 (min 90 ratio)))

(define (split-layout-controls? tree id direction)
  (cond
    [(split-layout-pane? tree) #f]
    [else
     (or (and (equal? (cadr tree) direction) (member id (split-layout-ids tree)) #t)
         (split-layout-controls? (caddr tree) id direction)
         (split-layout-controls? (cadddr tree) id direction))]))

(define (split-layout-resize tree id axis delta)
  (define direction (if (equal? axis "width") "right" "down"))
  (cond
    [(split-layout-pane? tree) tree]
    [else
     (define in-first (member id (split-layout-ids (caddr tree))))
     (define in-second (member id (split-layout-ids (cadddr tree))))
     (define child (if in-first (caddr tree) (cadddr tree)))
     (cond
       [(not (or in-first in-second)) tree]
       [(split-layout-controls? child id direction)
        (if in-first
            (list "split" (cadr tree) (split-layout-resize child id axis delta) (cadddr tree) (list-ref tree 4))
            (list "split" (cadr tree) (caddr tree) (split-layout-resize child id axis delta) (list-ref tree 4)))]
       [(equal? (cadr tree) direction)
        (list "split" (cadr tree) (caddr tree) (cadddr tree)
              (split-layout-ratio-clamped (if in-first (+ (list-ref tree 4) delta) (- (list-ref tree 4) delta))))]
       [else tree])]))

(define (split-layout-swap tree id-a id-b)
  (cond
    [(split-layout-pane? tree)
     (cond [(equal? (cadr tree) id-a) (list "pane" id-b)]
           [(equal? (cadr tree) id-b) (list "pane" id-a)]
           [else tree])]
    [else
     (list "split" (cadr tree) (split-layout-swap (caddr tree) id-a id-b) (split-layout-swap (cadddr tree) id-a id-b) (list-ref tree 4))]))

(define (split-layout-edit-parent tree id edit)
  (cond
    [(split-layout-pane? tree) tree]
    [(or (equal? (caddr tree) (list "pane" id)) (equal? (cadddr tree) (list "pane" id))) (edit tree)]
    [else
     (list "split" (cadr tree)
           (split-layout-edit-parent (caddr tree) id edit)
           (split-layout-edit-parent (cadddr tree) id edit)
           (list-ref tree 4))]))

(define (split-layout-flip tree id)
  (split-layout-edit-parent tree id
    (lambda (node) (list "split" (cadr node) (cadddr node) (caddr node) (- 100 (list-ref node 4))))))

(define (split-layout-turn tree id)
  (split-layout-edit-parent tree id
    (lambda (node) (list "split" (if (equal? (cadr node) "right") "down" "right") (caddr node) (cadddr node) (list-ref node 4)))))

(define (split-layout-equalise tree)
  (if (split-layout-pane? tree)
      tree
      (list "split" (cadr tree) (split-layout-equalise (caddr tree)) (split-layout-equalise (cadddr tree)) 50)))
