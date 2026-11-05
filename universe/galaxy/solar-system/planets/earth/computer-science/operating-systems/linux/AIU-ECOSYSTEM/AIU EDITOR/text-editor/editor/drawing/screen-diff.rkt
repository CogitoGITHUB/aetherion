#lang racket/base
(require (only-in "screen-grid.rkt" make-pane-grid pane-grid-feed! pane-grid-rows pane-grid-cursor-row pane-grid-cursor-column pane-grid-shown))
(provide screen-diff! screen-forget!)

(define front-rows (box #f))
(define front-size (box #f))
(define front-cursor (box #f))

(define (screen-forget!) (set-box! front-rows #f))

(define (cursor-of grid)
  (list (pane-grid-cursor-row grid) (pane-grid-cursor-column grid) (pane-grid-shown grid)))

(define (changed-span new-cells old-cells columns)
  (define from
    (for/first ([c (in-range columns)]
                #:when (not (equal? (vector-ref new-cells c) (vector-ref old-cells c))))
      c))
  (define to
    (and from
         (for/last ([c (in-range from columns)]
                    #:when (not (equal? (vector-ref new-cells c) (vector-ref old-cells c))))
           c)))
  (values from to))

(define (write-span! out cells row from to)
  (define start (if (and (> from 0) (char=? (car (vector-ref cells from)) #\nul)) (sub1 from) from))
  (write-string (format "\u001b[~a;~aH" (add1 row) (add1 start)) out)
  (for/fold ([style #f]) ([c (in-range start (add1 to))])
    (define cell (vector-ref cells c))
    (cond
      [(char=? (car cell) #\nul) style]
      [else
       (unless (equal? style (cdr cell))
         (write-string "\u001b[0m" out)
         (write-string (cdr cell) out))
       (write-char (car cell) out)
       (cdr cell)]))
  (write-string "\u001b[0m" out))

(define (screen-diff! text columns rows)
  (define back (make-pane-grid columns rows))
  (pane-grid-feed! back text)
  (define fresh? (or (not (unbox front-rows)) (not (equal? (unbox front-size) (cons columns rows)))))
  (define old (if fresh? (pane-grid-rows (make-pane-grid columns rows)) (unbox front-rows)))
  (define new (pane-grid-rows back))
  (define body (open-output-string))
  (define wrote? (box fresh?))
  (for ([r (in-range rows)])
    (define-values (from to) (changed-span (vector-ref new r) (vector-ref old r) columns))
    (when from
      (set-box! wrote? #t)
      (write-span! body (vector-ref new r) r from to)))
  (define cursor (cursor-of back))
  (define moved? (not (equal? cursor (unbox front-cursor))))
  (set-box! front-rows new)
  (set-box! front-size (cons columns rows))
  (set-box! front-cursor cursor)
  (cond
    [(not (or (unbox wrote?) moved?)) ""]
    [else
     (string-append "\u001b[?2026h\u001b[?25l"
                    (if fresh? "\u001b[0m\u001b[2J" "")
                    (get-output-string body)
                    (if (pane-grid-shown back)
                        (format "\u001b[~a;~aH\u001b[?25h" (add1 (car cursor)) (add1 (cadr cursor)))
                        "")
                    "\u001b[?2026l")]))