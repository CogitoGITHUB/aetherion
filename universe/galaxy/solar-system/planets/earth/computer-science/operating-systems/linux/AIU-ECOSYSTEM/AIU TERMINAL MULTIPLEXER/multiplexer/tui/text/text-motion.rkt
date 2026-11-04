#lang racket/base
(require racket/list racket/string)

(define (multi-cont? b) (= (bitwise-and b 192) 128))

(define (multi-left bs i)
  (let loop ([j (max 0 (sub1 (min i (bytes-length bs))))])
    (if (and (> j 0) (multi-cont? (bytes-ref bs j))) (loop (sub1 j)) j)))

(define (multi-right bs i)
  (let ([n (bytes-length bs)])
    (let loop ([j (min n (add1 i))])
      (if (and (< j n) (multi-cont? (bytes-ref bs j))) (loop (add1 j)) j))))

(define (multi-line-start bs i)
  (let loop ([j (min i (bytes-length bs))])
    (if (or (<= j 0) (= (bytes-ref bs (sub1 j)) 10)) (max j 0) (loop (sub1 j)))))

(define (multi-line-end bs i)
  (let ([n (bytes-length bs)])
    (let loop ([j (min i n)])
      (if (or (>= j n) (= (bytes-ref bs j) 10)) j (loop (add1 j))))))

(define (multi-col bs i)
  (for/sum ([k (in-range (multi-line-start bs i) (min i (bytes-length bs)))])
    (if (multi-cont? (bytes-ref bs k)) 0 1)))

(define (multi-at-col bs ls le c)
  (let loop ([j ls] [k 0])
    (if (or (>= j le) (>= k c)) j (loop (multi-right bs j) (add1 k)))))

(define (multi-up bs i)
  (let ([ls (multi-line-start bs i)])
    (if (= ls 0)
        i
        (let* ([pe (sub1 ls)] [ps (multi-line-start bs pe)])
          (multi-at-col bs ps pe (multi-col bs i))))))

(define (multi-down bs i)
  (let ([le (multi-line-end bs i)] [n (bytes-length bs)])
    (if (>= le n)
        i
        (let* ([ns (add1 le)] [ne (multi-line-end bs ns)])
          (multi-at-col bs ns ne (multi-col bs i))))))

(define (multi-word? b)
  (or (and (>= b 48) (<= b 57)) (and (>= b 65) (<= b 90)) (and (>= b 97) (<= b 122)) (= b 95) (>= b 128)))

(define (multi-word-fwd bs i)
  (let ([n (bytes-length bs)])
    (let skip ([j (min i n)])
      (cond [(>= j n) n]
            [(multi-word? (bytes-ref bs j))
             (let eat ([k j]) (if (and (< k n) (multi-word? (bytes-ref bs k))) (eat (add1 k)) k))]
            [else (skip (add1 j))]))))

(define (multi-word-back bs i)
  (let skip ([j (min i (bytes-length bs))])
    (cond [(<= j 0) 0]
          [(multi-word? (bytes-ref bs (sub1 j)))
           (let eat ([k j]) (if (and (> k 0) (multi-word? (bytes-ref bs (sub1 k)))) (eat (sub1 k)) k))]
          [else (skip (sub1 j))])))

(define (multi-word-at bs i)
  (let* ([n (bytes-length bs)]
         [p (min i n)]
         [a (let loop ([k p]) (if (and (> k 0) (multi-word? (bytes-ref bs (sub1 k)))) (loop (sub1 k)) k))]
         [b (let loop ([k p]) (if (and (< k n) (multi-word? (bytes-ref bs k))) (loop (add1 k)) k))])
    (cons a b)))


(provide multi-cont? multi-left multi-right multi-line-start multi-line-end multi-col multi-at-col multi-up multi-down multi-word? multi-word-fwd multi-word-back multi-word-at)
