#lang racket/base

(require racket/list)

(provide split-layout-single split-layout-split split-layout-close split-layout-ids split-layout-rects split-layout-neighbour)

(define (split-layout-single id) (list "pane" id))

(define (split-layout-pane? tree) (equal? (car tree) "pane"))

(define (split-layout-split tree focus-id new-id direction)
  (cond
    [(split-layout-pane? tree)
     (if (equal? (cadr tree) focus-id)
         (list "split" direction tree (list "pane" new-id))
         tree)]
    [else
     (list "split" (cadr tree)
           (split-layout-split (caddr tree) focus-id new-id direction)
           (split-layout-split (cadddr tree) focus-id new-id direction))]))

(define (split-layout-close tree id)
  (cond
    [(split-layout-pane? tree) (if (equal? (cadr tree) id) #f tree)]
    [else
     (define first-tree (split-layout-close (caddr tree) id))
     (define second-tree (split-layout-close (cadddr tree) id))
     (cond
       [(not first-tree) second-tree]
       [(not second-tree) first-tree]
       [else (list "split" (cadr tree) first-tree second-tree)])]))

(define (split-layout-ids tree)
  (if (split-layout-pane? tree)
      (list (cadr tree))
      (append (split-layout-ids (caddr tree)) (split-layout-ids (cadddr tree)))))

(define (split-layout-rects tree left top width height)
  (cond
    [(split-layout-pane? tree) (list (list (cadr tree) left top width height))]
    [(equal? (cadr tree) "right")
     (define first-width (quotient width 2))
     (append (split-layout-rects (caddr tree) left top first-width height)
             (split-layout-rects (cadddr tree) (+ left first-width) top (- width first-width) height))]
    [else
     (define first-height (quotient height 2))
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
