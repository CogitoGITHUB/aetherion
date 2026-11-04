#lang racket/base
(require racket/string "../float/box-shared.rkt")

(define notify-repaint (box void))

(define notes (box null))

(define (level-seconds level)
  (cond [(string=? level "error") 5] [(string=? level "warn") 3] [else 2]))

(define (keep-last items n)
  (if (> (length items) n) (keep-last (cdr items) n) items))

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

(define (wrap text n)
  (let loop ([words (string-split text " ")] [line ""] [out null])
    (cond
      [(null? words) (reverse (if (string=? line "") out (cons line out)))]
      [else
       (define try (if (string=? line "") (car words) (string-append line " " (car words))))
       (cond [(and (> (string-length try) n) (not (string=? line "")))
              (loop words "" (cons line out))]
             [else (loop (cdr words) (if (> (string-length try) n) (substring try 0 n) try) out)])])))

(define (note-lines note w)
  (define level (car note))
  (define rows
    (append (list (edge-line "╭" "╮" level "" w))
            (map (lambda (l) (body-line l w)) (wrap (cadr note) (- w 4)))
            (list (rule-line "╰" "╯" w))))
  (define color (if (string=? level "error") "\u001b[31m" "\u001b[97m"))
  (map (lambda (r) (string-append color r "\u001b[0m")) rows))

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
