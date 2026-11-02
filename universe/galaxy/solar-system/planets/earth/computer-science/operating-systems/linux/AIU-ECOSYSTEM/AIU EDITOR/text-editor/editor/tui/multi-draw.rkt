#lang racket/base
;; One job: draw the cursors and the selections of multi.rkt - the lit block ranges in the drawn page and the reverse video overlay on the raw text.

(require "text-motion.rkt" "../commands/commands.rkt" "../notation/document.rkt" "../notation/host.rkt" (only-in "blockview.rkt" blockview-inside))

(provide multi-lit multi-text-overlay)

;; multi-lit answers the line ranges to light in the drawn page for the cursors and the selections: the block
;; under a cursor, and every block that lies inside a selection.
(define (multi-lit got ranges point)
  (let* ([blocks (filter (lambda (b) (hash-has-key? ranges (block-start b))) (page-blocks got))]
         [cs (cons (cons point (unbox main-anchor)) (unbox extra-cursors))])
    (apply append
           (for/list ([c (in-list cs)])
             (let ([h (car c)] [a (cdr c)])
               (cond
                 [(and a (not (= a h)))
                  (let ([lo (min a h)] [hi (max a h)])
                    (for/list ([b (in-list blocks)]
                               #:when (and (>= (block-start b) lo) (<= (block-end b) hi)))
                      (hash-ref ranges (block-start b))))]
                 [else
                  (let ([b (blockview-inside blocks h)])
                    (if b (list (hash-ref ranges (block-start b))) (list)))]))))))

;; multi-visible-lines answers the (start . end) of each visible line of the raw text.
(define (multi-visible-lines bs top-line visible)
  (let loop ([pos 0] [ln 1])
    (cond
      [(= ln top-line)
       (let take ([ls pos] [k 0] [out (list)])
         (if (or (>= k visible) (> ls (bytes-length bs)))
             (reverse out)
             (let ([le (multi-line-end bs ls)])
               (take (add1 le) (add1 k) (cons (cons ls le) out)))))]
      [else (loop (add1 (multi-line-end bs pos)) (add1 ln))])))

;; multi-seg answers the escape text that draws one piece of a line in reverse video; eol? adds a blank cell
;; for the end of the line.
(define (multi-seg bs ls a b eol? row left width)
  (let* ([col (for/sum ([k (in-range ls a)]) (if (multi-cont? (bytes-ref bs k)) 0 1))]
         [txt (string-append (bytes->string/utf-8 (subbytes bs a b) #\?) (if eol? " " ""))]
         [room (- width col)])
    (if (or (<= room 0) (string=? txt ""))
        ""
        (string-append "\u001b[" (number->string row) ";" (number->string (+ left col 1)) "H\u001b[7m"
                       (if (> (string-length txt) room) (substring txt 0 room) txt)
                       "\u001b[0m"))))

;; multi-text-overlay answers the escape text that draws the selections and the cursors over the raw text:
;; the main cursor is drawn too, except in the write layer where the terminal cursor is it.
(define (multi-text-overlay raw top visible offset left width layer point)
  (let* ([bs (string->bytes/utf-8 raw)]
         [n (bytes-length bs)]
         [nlines (add1 (for/sum ([b (in-bytes bs)]) (if (= b 10) 1 0)))]
         [top-line (max 1 (min top nlines))]
         [lines (multi-visible-lines bs top-line visible)]
         [cs (append (if (string=? layer "write") (list) (list (cons point (unbox main-anchor))))
                     (unbox extra-cursors))]
         [ivs (for/list ([c (in-list cs)] #:when (and (cdr c) (not (= (cdr c) (car c))))) 
                (cons (min (car c) (cdr c)) (max (car c) (cdr c))))]
         [marks (map car cs)])
    (apply string-append
           (for/list ([ln (in-list lines)] [i (in-naturals)])
             (let ([ls (car ln)] [le (cdr ln)] [row (+ offset i 1)])
               (apply string-append
                      (append
                       (for/list ([iv (in-list ivs)])
                         (let* ([lo (car iv)] [hi (cdr iv)]
                                [a (max lo ls)] [b (min hi le)]
                                [eol? (and (<= lo le) (> hi le) (< le n))])
                           (if (or (< a b) eol?)
                               (multi-seg bs ls a (max a b) eol? row left width)
                               "")))
                       (for/list ([p (in-list marks)])
                         (cond [(and (>= p ls) (< p le)) (multi-seg bs ls p (multi-right bs p) #f row left width)]
                               [(= p le) (multi-seg bs ls le le #t row left width)]
                               [else ""])))))))))
