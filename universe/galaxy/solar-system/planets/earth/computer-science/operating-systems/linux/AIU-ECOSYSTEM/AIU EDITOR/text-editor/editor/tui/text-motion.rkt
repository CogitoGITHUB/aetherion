#lang racket/base
;; One job: the motion of a cursor over the bytes of a text: left, right, line start and end, up, down and words.
(require racket/list racket/string)

;; multi-cont? asks whether a byte is the inside of a multi byte character.
(define (multi-cont? b) (= (bitwise-and b 192) 128))

;; multi-left answers the start of the character before an offset.
(define (multi-left bs i)
  (let loop ([j (max 0 (sub1 (min i (bytes-length bs))))])
    (if (and (> j 0) (multi-cont? (bytes-ref bs j))) (loop (sub1 j)) j)))

;; multi-right answers the start of the character after an offset.
(define (multi-right bs i)
  (let ([n (bytes-length bs)])
    (let loop ([j (min n (add1 i))])
      (if (and (< j n) (multi-cont? (bytes-ref bs j))) (loop (add1 j)) j))))

;; multi-line-start answers the start of the line an offset is on.
(define (multi-line-start bs i)
  (let loop ([j (min i (bytes-length bs))])
    (if (or (<= j 0) (= (bytes-ref bs (sub1 j)) 10)) (max j 0) (loop (sub1 j)))))

;; multi-line-end answers the end of the line an offset is on.
(define (multi-line-end bs i)
  (let ([n (bytes-length bs)])
    (let loop ([j (min i n)])
      (if (or (>= j n) (= (bytes-ref bs j) 10)) j (loop (add1 j))))))

;; multi-col answers the column of an offset in characters.
(define (multi-col bs i)
  (for/sum ([k (in-range (multi-line-start bs i) (min i (bytes-length bs)))])
    (if (multi-cont? (bytes-ref bs k)) 0 1)))

;; multi-at-col answers the offset of a column in the line that runs from ls to le, kept inside the line.
(define (multi-at-col bs ls le c)
  (let loop ([j ls] [k 0])
    (if (or (>= j le) (>= k c)) j (loop (multi-right bs j) (add1 k)))))

;; multi-up answers the offset one line up in the same column, or the same offset on the first line.
(define (multi-up bs i)
  (let ([ls (multi-line-start bs i)])
    (if (= ls 0)
        i
        (let* ([pe (sub1 ls)] [ps (multi-line-start bs pe)])
          (multi-at-col bs ps pe (multi-col bs i))))))

;; multi-down answers the offset one line down in the same column, or the same offset on the last line.
(define (multi-down bs i)
  (let ([le (multi-line-end bs i)] [n (bytes-length bs)])
    (if (>= le n)
        i
        (let* ([ns (add1 le)] [ne (multi-line-end bs ns)])
          (multi-at-col bs ns ne (multi-col bs i))))))

;; multi-word? asks whether a byte belongs to a word.
(define (multi-word? b)
  (or (and (>= b 48) (<= b 57)) (and (>= b 65) (<= b 90)) (and (>= b 97) (<= b 122)) (= b 95) (>= b 128)))

;; multi-word-fwd answers the end of the next word.
(define (multi-word-fwd bs i)
  (let ([n (bytes-length bs)])
    (let skip ([j (min i n)])
      (cond [(>= j n) n]
            [(multi-word? (bytes-ref bs j))
             (let eat ([k j]) (if (and (< k n) (multi-word? (bytes-ref bs k))) (eat (add1 k)) k))]
            [else (skip (add1 j))]))))

;; multi-word-back answers the start of the word before an offset.
(define (multi-word-back bs i)
  (let skip ([j (min i (bytes-length bs))])
    (cond [(<= j 0) 0]
          [(multi-word? (bytes-ref bs (sub1 j)))
           (let eat ([k j]) (if (and (> k 0) (multi-word? (bytes-ref bs (sub1 k)))) (eat (sub1 k)) k))]
          [else (skip (sub1 j))])))

;; multi-word-at answers the word under an offset as (start . end); the two are equal when there is none.
(define (multi-word-at bs i)
  (let* ([n (bytes-length bs)]
         [p (min i n)]
         [a (let loop ([k p]) (if (and (> k 0) (multi-word? (bytes-ref bs (sub1 k)))) (loop (sub1 k)) k))]
         [b (let loop ([k p]) (if (and (< k n) (multi-word? (bytes-ref bs k))) (loop (add1 k)) k))])
    (cons a b)))


(provide multi-cont? multi-left multi-right multi-line-start multi-line-end multi-col multi-at-col multi-up multi-down multi-word? multi-word-fwd multi-word-back multi-word-at)
