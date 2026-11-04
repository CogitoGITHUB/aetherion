#lang racket/base

(require racket/list racket/string "split-layout.rkt")

(provide (all-from-out "split-layout.rkt") split-paint-fit-plain split-pane-box split-compose)

(define (split-paint-fit-plain text width)
  (define size (string-length text))
  (cond
    [(> size width) (substring text 0 width)]
    [else (string-append text (make-string (- width size) #\space))]))

(define (split-pane-box fit title lines width height focused?)
  (define inner (max 1 (- width 2)))
  (define corner-left-top (if focused? "┏" "╭"))
  (define corner-right-top (if focused? "┓" "╮"))
  (define corner-left-bottom (if focused? "┗" "╰"))
  (define corner-right-bottom (if focused? "┛" "╯"))
  (define rule (if focused? "━" "─"))
  (define edge (if focused? "┃" "│"))
  (define shown-title (if (> (+ (string-length title) 3) inner) (substring title 0 (max 0 (- inner 3))) title))
  (define used (+ 3 (string-length shown-title)))
  (define top-line
    (string-append corner-left-top rule " " shown-title " "
                   (apply string-append (for/list ([i (in-range (max 0 (- inner used)))]) rule))
                   corner-right-top))
  (define bottom-line
    (string-append corner-left-bottom (apply string-append (for/list ([i (in-range inner)]) rule)) corner-right-bottom))
  (define body-rows (max 0 (- height 2)))
  (append (list top-line)
          (for/list ([i (in-range body-rows)])
            (string-append edge (fit (if (< i (length lines)) (list-ref lines i) "") inner) edge))
          (list bottom-line)))

(define (split-compose rects boxes height)
  (string-join
   (for/list ([y (in-range height)])
     (apply string-append
            (for/list ([rect (in-list (sort (filter (lambda (r) (and (>= y (caddr r)) (< y (+ (caddr r) (list-ref r 4))))) rects)
                                            < #:key cadr))])
              (list-ref (hash-ref boxes (car rect)) (- y (caddr rect))))))
   "\n"))
