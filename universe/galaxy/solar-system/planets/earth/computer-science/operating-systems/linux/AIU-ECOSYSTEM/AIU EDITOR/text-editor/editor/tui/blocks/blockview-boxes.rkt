#lang racket/base

(require racket/list racket/string "../../notation/document.rkt" "../../notation/host.rkt")

(provide blockview-plain (struct-out blockview-box) blockview-prefix blockview-end blockview-boxes blockview-kids blockview-seen blockview-assign blockview-ranges blockview-drawn blockview-inside blockview-target blockview-parent)

(define (blockview-plain line)
  (regexp-replace* #px"\u001b\\[[0-9;]*m" line ""))

(struct blockview-box (from to kids))

(define (blockview-prefix depth)
  (apply string-append (for/list ([i (in-range depth)]) "│ ")))

(define (blockview-end lines from limit close-rx label-rx)
  (let loop ([j (add1 from)] [labelled? #f])
    (cond
      [(>= j limit) #f]
      [(regexp-match? close-rx (vector-ref lines j))
       (if (and (not labelled?) (regexp-match? label-rx (vector-ref lines j)))
           (loop (add1 j) #t)
           j)]
      [else (loop (add1 j) labelled?)])))

(define (blockview-boxes lines from limit depth)
  (define prefix (regexp-quote (blockview-prefix depth)))
  (define top-rx (regexp (string-append "^" prefix "╭─")))
  (define close-rx (regexp (string-append "^" prefix "╰")))
  (define label-rx (regexp (string-append "^" prefix "╰─ ")))
  (let loop ([i from] [out null])
    (cond
      [(>= i limit) (reverse out)]
      [(regexp-match? top-rx (vector-ref lines i))
       (define end (blockview-end lines i limit close-rx label-rx))
       (if end
           (loop (add1 end)
                 (cons (blockview-box i end (blockview-boxes lines (add1 i) end (add1 depth))) out))
           (loop (add1 i) out))]
      [else (loop (add1 i) out)])))

(define (blockview-kids blocks b)
  (filter (lambda (k)
            (and (= (block-depth k) (add1 (block-depth b)))
                 (>= (block-start k) (block-start b))
                 (<= (block-end k) (block-end b))))
          blocks))

(define (blockview-seen blocks b)
  (define kids
    (filter (lambda (k) (not (string=? (block-name k) "answer")))
            (blockview-kids blocks b)))
  (if (and (string=? (block-name b) "section")
           (pair? kids)
           (string=? (block-name (car kids)) "title"))
      (cdr kids)
      kids))

(define (blockview-assign blocks wanted boxes ranges)
  (if (= (length wanted) (length boxes))
      (for/fold ([found ranges]) ([b (in-list wanted)] [bx (in-list boxes)])
        (define next
          (hash-set found (block-start b) (cons (blockview-box-from bx) (blockview-box-to bx))))
        (if (member (block-name b) (list "section" "comment"))
            (blockview-assign blocks (blockview-seen blocks b) (blockview-box-kids bx) next)
            next))
      ranges))

(define (blockview-ranges got lines)
  (define plain (list->vector (map blockview-plain lines)))
  (define blocks (page-blocks got))
  (define top
    (filter (lambda (b)
              (and (= (block-depth b) 0) (not (string=? (block-name b) "answer"))))
            blocks))
  (blockview-assign blocks top (blockview-boxes plain 0 (vector-length plain) 0) (hash)))

(define (blockview-drawn blocks)
  (define hidden
    (for/list ([b (in-list blocks)] #:when (string=? (block-name b) "section"))
      (define kids (blockview-kids blocks b))
      (if (and (pair? kids) (string=? (block-name (car kids)) "title"))
          (block-start (car kids))
          -1)))
  (filter (lambda (b)
            (and (not (string=? (block-name b) "answer"))
                 (not (memv (block-start b) hidden))))
          blocks))

(define (blockview-inside blocks point)
  (define inside
    (filter (lambda (b) (and (<= (block-start b) point) (< point (block-end b))))
            blocks))
  (if (null? inside) #f (argmax block-depth inside)))

(define (blockview-target blocks point ranges)
  (blockview-inside (filter (lambda (b) (hash-has-key? ranges (block-start b))) blocks)
             point))

(define (blockview-parent blocks b)
  (define ups
    (filter (lambda (p)
              (and (= (block-depth p) (sub1 (block-depth b)))
                   (<= (block-start p) (block-start b))
                   (>= (block-end p) (block-end b))))
            blocks))
  (if (null? ups) #f (argmax block-start ups)))
