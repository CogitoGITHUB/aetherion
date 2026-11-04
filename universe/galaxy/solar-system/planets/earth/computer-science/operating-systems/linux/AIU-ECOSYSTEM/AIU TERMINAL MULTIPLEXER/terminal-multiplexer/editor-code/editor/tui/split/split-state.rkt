#lang racket/base

(require racket/list "split-layout.rkt")

(provide split-files split-state-file-set! split-state-file-of split-tree split-focus split-state-split! split-state-close! split-state-focus! split-state-swap! split-state-resize! split-state-flip! split-state-turn! split-state-equalise!)

(define split-tree (box (split-layout-single 1)))

(define split-focus (box 1))

(define split-last-id (box 1))

(define split-files (box (hash)))

(define (split-state-file-set! file)
  (set-box! split-files (hash-set (unbox split-files) (unbox split-focus) file)))

(define (split-state-file-of id)
  (hash-ref (unbox split-files) id #f))

(define split-screen-size 1000)

(define (split-state-split! direction)
  (define id (add1 (unbox split-last-id)))
  (set-box! split-last-id id)
  (set-box! split-files (hash-set (unbox split-files) id (split-state-file-of (unbox split-focus))))
  (set-box! split-tree (split-layout-split (unbox split-tree) (unbox split-focus) id direction))
  (set-box! split-focus id)
  id)

(define (split-state-close!)
  (define rest (split-layout-close (unbox split-tree) (unbox split-focus)))
  (cond
    [(not rest) #f]
    [else
     (set-box! split-files (hash-remove (unbox split-files) (unbox split-focus)))
     (set-box! split-tree rest)
     (set-box! split-focus (car (split-layout-ids rest)))
     #t]))

(define (split-state-neighbour direction)
  (split-layout-neighbour (unbox split-tree) (unbox split-focus) direction split-screen-size split-screen-size))

(define (split-state-focus! direction)
  (define other (split-state-neighbour direction))
  (and other (begin (set-box! split-focus other) #t)))

(define (split-state-swap! direction)
  (define other (split-state-neighbour direction))
  (and other (begin (set-box! split-tree (split-layout-swap (unbox split-tree) (unbox split-focus) other)) #t)))

(define (split-state-resize! axis delta)
  (define before (unbox split-tree))
  (set-box! split-tree (split-layout-resize before (unbox split-focus) axis delta))
  (not (equal? before (unbox split-tree))))

(define (split-state-flip!)
  (set-box! split-tree (split-layout-flip (unbox split-tree) (unbox split-focus)))
  #t)

(define (split-state-turn!)
  (set-box! split-tree (split-layout-turn (unbox split-tree) (unbox split-focus)))
  #t)

(define (split-state-equalise!)
  (set-box! split-tree (split-layout-equalise (unbox split-tree)))
  #t)
