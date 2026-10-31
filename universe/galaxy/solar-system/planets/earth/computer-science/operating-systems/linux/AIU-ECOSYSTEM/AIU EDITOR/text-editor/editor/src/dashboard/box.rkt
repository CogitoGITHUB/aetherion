#lang racket/base
;; One job: the box drawing the bar and the tabs have in common: the edges, the
;; rows of text, the white colour, a shared edge and the placing of rows at a
;; row and a column of the screen.

(require racket/string)

;; box-pad answers a string padded with spaces on the right to n characters.
(define (box-pad s n)
  (string-append s (make-string (max 0 (- n (string-length s))) #\space)))

;; edge-line answers one edge of a box: a corner, a title on the left, a text on
;; the right and the closing corner, exactly width characters long. The text on
;; the right is dropped when it does not fit.
(define (edge-line l r left right width)
  (define head (string-append l "─ " left " "))
  (define tail0 (if (string=? right "") "" (string-append " " right " ")))
  (define tail (if (< (+ (string-length head) (string-length tail0) 2) width) tail0 ""))
  (define h (if (> (+ (string-length head) 1) width) (substring head 0 (max 0 (- width 1))) head))
  (string-append h (make-string (max 0 (- width (string-length h) (string-length tail) 1)) #\─) tail r))

;; rule-line answers a plain edge of a box.
(define (rule-line l r width)
  (string-append l (make-string (max 0 (- width 2)) #\─) r))

;; body-line answers one row of text inside a box, cut and padded.
(define (body-line text width)
  (define inner (max 1 (- width 4)))
  (define t (if (> (string-length text) inner) (substring text 0 inner) text))
  (string-append "│ " (box-pad t inner) " │"))

;; join-edge turns the top edge of a box into a shared edge: the corners become
;; tee corners, so the box can sit under another one and share its line.
(define (join-edge line)
  (string-append "├" (substring line 1 (sub1 (string-length line))) "┤"))

;; draw-at answers the escape text that writes rows at a row and a column.
(define (draw-at lines row col)
  (string-join
   (for/list ([l (in-list lines)] [i (in-naturals)])
     (string-append "\u001b[" (number->string (+ row i)) ";" (number->string col) "H" l))
   ""))

;; white answers a text drawn in white, with no background.
(define (white s) (string-append "\u001b[97m" s "\u001b[0m"))

;; The box drawing, for the bar and the tabs.
(provide box-pad edge-line rule-line body-line join-edge draw-at white)
