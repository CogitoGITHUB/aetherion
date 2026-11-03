#lang racket/base

(require racket/string)

(define (box-pad s n)
  (string-append s (make-string (max 0 (- n (string-length s))) #\space)))

(define (edge-line l r left right width)
  (define head (string-append l "─ " left " "))
  (define tail0 (if (string=? right "") "" (string-append " " right " ")))
  (define tail (if (< (+ (string-length head) (string-length tail0) 2) width) tail0 ""))
  (define h (if (> (+ (string-length head) 1) width) (substring head 0 (max 0 (- width 1))) head))
  (string-append h (make-string (max 0 (- width (string-length h) (string-length tail) 1)) #\─) tail r))

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
