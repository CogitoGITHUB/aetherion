#lang racket/base
;; One job: the motion of a cursor over the bytes of a text: left, right, line start and end, up, down and words.
(require racket/list racket/string)

;; mu-cont? asks whether a byte is the inside of a multi byte character.
(define (mu-cont? b) (= (bitwise-and b 192) 128))

;; mu-left answers the start of the character before an offset.
(define (mu-left bs i)
  (let loop ([j (max 0 (sub1 (min i (bytes-length bs))))])
    (if (and (> j 0) (mu-cont? (bytes-ref bs j))) (loop (sub1 j)) j)))

;; mu-right answers the start of the character after an offset.
(define (mu-right bs i)
  (let ([n (bytes-length bs)])
    (let loop ([j (min n (add1 i))])
      (if (and (< j n) (mu-cont? (bytes-ref bs j))) (loop (add1 j)) j))))

;; mu-line-start answers the start of the line an offset is on.
(define (mu-line-start bs i)
  (let loop ([j (min i (bytes-length bs))])
    (if (or (<= j 0) (= (bytes-ref bs (sub1 j)) 10)) (max j 0) (loop (sub1 j)))))

;; mu-line-end answers the end of the line an offset is on.
(define (mu-line-end bs i)
  (let ([n (bytes-length bs)])
    (let loop ([j (min i n)])
      (if (or (>= j n) (= (bytes-ref bs j) 10)) j (loop (add1 j))))))

;; mu-col answers the column of an offset in characters.
(define (mu-col bs i)
  (for/sum ([k (in-range (mu-line-start bs i) (min i (bytes-length bs)))])
    (if (mu-cont? (bytes-ref bs k)) 0 1)))

;; mu-at-col answers the offset of a column in the line that runs from ls to le, kept inside the line.
(define (mu-at-col bs ls le c)
  (let loop ([j ls] [k 0])
    (if (or (>= j le) (>= k c)) j (loop (mu-right bs j) (add1 k)))))

;; mu-up answers the offset one line up in the same column, or the same offset on the first line.
(define (mu-up bs i)
  (let ([ls (mu-line-start bs i)])
    (if (= ls 0)
        i
        (let* ([pe (sub1 ls)] [ps (mu-line-start bs pe)])
          (mu-at-col bs ps pe (mu-col bs i))))))

;; mu-down answers the offset one line down in the same column, or the same offset on the last line.
(define (mu-down bs i)
  (let ([le (mu-line-end bs i)] [n (bytes-length bs)])
    (if (>= le n)
        i
        (let* ([ns (add1 le)] [ne (mu-line-end bs ns)])
          (mu-at-col bs ns ne (mu-col bs i))))))

;; mu-word? asks whether a byte belongs to a word.
(define (mu-word? b)
  (or (and (>= b 48) (<= b 57)) (and (>= b 65) (<= b 90)) (and (>= b 97) (<= b 122)) (= b 95) (>= b 128)))

;; mu-word-fwd answers the end of the next word.
(define (mu-word-fwd bs i)
  (let ([n (bytes-length bs)])
    (let skip ([j (min i n)])
      (cond [(>= j n) n]
            [(mu-word? (bytes-ref bs j))
             (let eat ([k j]) (if (and (< k n) (mu-word? (bytes-ref bs k))) (eat (add1 k)) k))]
            [else (skip (add1 j))]))))

;; mu-word-back answers the start of the word before an offset.
(define (mu-word-back bs i)
  (let skip ([j (min i (bytes-length bs))])
    (cond [(<= j 0) 0]
          [(mu-word? (bytes-ref bs (sub1 j)))
           (let eat ([k j]) (if (and (> k 0) (mu-word? (bytes-ref bs (sub1 k)))) (eat (sub1 k)) k))]
          [else (skip (sub1 j))])))

;; mu-word-at answers the word under an offset as (start . end); the two are equal when there is none.
(define (mu-word-at bs i)
  (let* ([n (bytes-length bs)]
         [p (min i n)]
         [a (let loop ([k p]) (if (and (> k 0) (mu-word? (bytes-ref bs (sub1 k)))) (loop (sub1 k)) k))]
         [b (let loop ([k p]) (if (and (< k n) (mu-word? (bytes-ref bs k))) (loop (add1 k)) k))])
    (cons a b)))


(provide mu-cont? mu-left mu-right mu-line-start mu-line-end mu-col mu-at-col mu-up mu-down mu-word? mu-word-fwd mu-word-back mu-word-at)
