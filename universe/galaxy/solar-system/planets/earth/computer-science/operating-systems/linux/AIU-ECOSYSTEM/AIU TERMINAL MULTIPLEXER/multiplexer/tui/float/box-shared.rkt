#lang racket/base

(require racket/string)

(define (box-pad s n)
  (string-append s (make-string (max 0 (- n (string-length s))) #\space)))

(define (edge-line l r left right0 width)
  (define parts (string-split right0 "\u0001" #:trim? #f))
  (define mid (if (> (length parts) 1) (car parts) ""))
  (define right
    (if (null? parts) "" (list-ref parts (- (length parts) 1))))
  (define head (string-append l "─┤ " left " ├"))
  (define tail0
    (if (string=? right "") "" (string-append "┤ " right " ├─")))
  (define tail
    (if (< (+ (string-length head) (string-length tail0) 2) width)
        tail0 ""))
  (define h
    (if (> (+ (string-length head) 1) width)
        (substring head 0 (max 0 (- width 1))) head))
  (define fill
    (max 0 (- width (string-length h) (string-length tail) 1)))
  (define midbox
    (if (string=? mid "") "" (string-append "┤ " mid " ├")))
  (define ml (string-length midbox))
  (define start
    (max 1 (min (- fill ml 1)
                (- (quotient (- width ml) 2) (string-length h)))))
  (if (or (string=? midbox "") (< fill (+ ml 2)))
      (string-append h (make-string fill #\─) tail r)
      (string-append h (make-string start #\─) midbox
                     (make-string (- fill start ml) #\─) tail r)))

(define (rule-line l r width)
  (string-append l (make-string (max 0 (- width 2)) #\─) r))

(define (body-line text width)
  (define inner (max 1 (- width 4)))
  (define t (if (> (string-length text) inner) (substring text 0 inner) text))
  (string-append "│ " (box-pad t inner) " │"))

(define (join-edge line)
  (string-append "├" (substring line 1 (sub1 (string-length line))) "┤"))

(define (draw-at lines row col)
  (string-join
   (for/list ([l (in-list lines)] [i (in-naturals)])
     (string-append "\u001b[" (number->string (+ row i)) ";" (number->string col) "H" l))
   ""))

(define (white s) (string-append "\u001b[97m" s "\u001b[0m"))

(define paint-ready (box #f))

(provide paint-ready box-pad edge-line rule-line body-line join-edge draw-at white)
