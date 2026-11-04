#lang racket/base
(provide char-columns)
(define (char-columns ch)
  (define n (char->integer ch))
  (cond
    [(< n 32) 0]
    [(< n 127) 1]
    [(< n 160) 0]
    [(memq (char-general-category ch) (quote (mn me cf))) 0]
    [(or (<= #x1100 n #x115F) (<= #x2E80 n #xA4CF) (<= #xAC00 n #xD7A3)
         (<= #xF900 n #xFAFF) (<= #xFE30 n #xFE6F) (<= #xFF00 n #xFF60)
         (<= #xFFE0 n #xFFE6) (<= #x1F300 n #x1F64F) (<= #x1F680 n #x1F6FF)
         (<= #x1F900 n #x1F9FF) (<= #x20000 n #x3FFFD)) 2]
    [else 1]))
