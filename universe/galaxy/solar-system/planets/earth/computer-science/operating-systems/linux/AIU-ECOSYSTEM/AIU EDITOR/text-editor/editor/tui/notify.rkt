#lang racket/base
;; notify.rkt: the notifications of the live editor. A notification is a
;; level, a text and an expiry. The list is drawn as floating boxes in the
;; top right corner through the overlay of a paint, and a thread removes each
;; one when its time is up and asks for a repaint. Only racket/base and the
;; box drawing are loaded, so the first paint is not touched.
(require racket/string "box.rkt")

;; notify-repaint holds the function that repaints the screen; the live
;; session puts it here.
(define notify-repaint (box void))

;; notes holds the live notifications, oldest first, as lists of a level, a
;; text and an expiry in milliseconds.
(define notes (box null))

;; level-seconds answers how long a notification of one level stays.
(define (level-seconds level)
  (cond [(string=? level "error") 5] [(string=? level "warn") 3] [else 2]))

;; keep-last answers the last n items of a list.
(define (keep-last items n)
  (if (> (length items) n) (keep-last (cdr items) n) items))

;; notify! adds one notification, replacing an identical text, and starts the
;; thread that removes it and repaints when its time is up.
(define (notify! level text)
  (define secs (level-seconds level))
  (define expiry (+ (current-inexact-milliseconds) (* 1000 secs)))
  (define others (filter (lambda (n) (not (string=? (cadr n) text))) (unbox notes)))
  (set-box! notes (keep-last (append others (list (list level text expiry))) 3))
  (thread
   (lambda ()
     (sleep (+ secs 0.05))
     (set-box! notes (filter (lambda (n) (> (caddr n) (current-inexact-milliseconds))) (unbox notes)))
     (with-handlers ([(lambda (e) #t) void]) ((unbox notify-repaint)))))
  (void))

;; wrap answers the text cut at spaces into lines of at most n characters.
(define (wrap text n)
  (let loop ([words (string-split text " ")] [line ""] [out null])
    (cond
      [(null? words) (reverse (if (string=? line "") out (cons line out)))]
      [else
       (define try (if (string=? line "") (car words) (string-append line " " (car words))))
       (cond [(and (> (string-length try) n) (not (string=? line "")))
              (loop words "" (cons line out))]
             [else (loop (cdr words) (if (> (string-length try) n) (substring try 0 n) try) out)])])))

;; note-lines answers the drawn rows of one notification, w characters wide.
(define (note-lines note w)
  (define level (car note))
  (define rows
    (append (list (edge-line "╭" "╮" level "" w))
            (map (lambda (l) (body-line l w)) (wrap (cadr note) (- w 4)))
            (list (rule-line "╰" "╯" w))))
  (define color (if (string=? level "error") "\u001b[31m" "\u001b[97m"))
  (map (lambda (r) (string-append color r "\u001b[0m")) rows))

;; notify-overlay answers the escape text that draws every live notification
;; from a row down at the right edge, or nothing when there are none.
(define (notify-overlay width height row)
  (define now (current-inexact-milliseconds))
  (define live (filter (lambda (n) (> (caddr n) now)) (unbox notes)))
  (define w (min 40 (- width 2)))
  (if (or (null? live) (< w 12))
      ""
      (let loop ([items live] [r row] [out ""])
        (cond
          [(null? items) out]
          [else
           (define lines (note-lines (car items) w))
           (if (> (+ r (length lines)) (- height 1))
               out
               (loop (cdr items) (+ r (length lines))
                     (string-append out (draw-at lines r (max 1 (+ (- width w) 1))))))]))))

(provide notify! notify-overlay notify-repaint)
