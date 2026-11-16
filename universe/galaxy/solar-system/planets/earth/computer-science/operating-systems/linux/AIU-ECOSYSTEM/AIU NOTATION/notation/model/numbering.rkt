#lang racket/base
(require racket/list
         racket/string
         "nodes.rkt"
         "outline.rkt"
         "properties.rkt"
         "../errors/raise.rkt")

(provide heading-numbers number-at block-numbers block-number-at)

(define (heading-numbers o)
  (define counters (box (list)))
  (define out (box (list)))
  (for ([node (in-list (outline-nodes o))])
    (walk node 0 counters out))
  (reverse (unbox out)))

(define (walk node depth counters out)
  (when (block-node? node)
    (define inner
      (if (eq? (block-node-name node) (quote chapter))
          (add1 depth)
          depth))
    (when (> inner depth)
      (define taken (take-number (unbox counters) inner))
      (set-box! counters taken)
      (set-box! out (cons (list (number-text taken inner)
                                inner
                                (block-node-line node))
                          (unbox out))))
    (for ([child (in-list (block-node-children node))])
      (walk child inner counters out))))

(define (take-number counters level)
  (define index (sub1 level))
  (define grown
    (if (> (length counters) index)
      (append counters (list))
      (append counters
              (make-list (- (add1 index) (length counters)) 0))))
  (define bumped (append grown (list)))
  (set! bumped
        (list-set bumped index (add1 (list-ref bumped index))))
  (take bumped (add1 index)))

(define (number-text counters level)
  (string-join (map number->string (take counters level)) "."))

(define (number-at o line)
  (define found
    (for/or ([entry (in-list (heading-numbers o))])
      (and (= (third entry) line) entry)))
  (and found (first found)))

(define unnumbered
  (list (quote title) (quote comment) (quote answer)
        (quote contract) (quote row) (quote header)
        (quote contents) (quote index) (quote bibliography) (quote pin)))

(define (block-label chapter local)
  (if (string=? chapter "")
      local
      (string-append chapter ">" local)))

(define (block-numbers o)
  (define chapters (heading-numbers o))
  (define out (box (list)))
  (number-nodes (outline-nodes o) "" "" (box 0) chapters out)
  (reverse (unbox out)))

(define (number-nodes nodes chapter chain count chapters out)
  (for ([node (in-list nodes)])
    (when (block-node? node)
      (define name (block-node-name node))
      (cond
        [(eq? name (quote chapter))
         (define found
           (for/or ([entry (in-list chapters)])
             (and (= (third entry) (block-node-line node))
                  (first entry))))
         (number-nodes (block-node-children node)
                       (or found "") "" (box 0) chapters out)]
        [(memq name unnumbered)
         (number-nodes (block-node-children node)
                       chapter chain count chapters out)]
        [else
         (set-box! count (add1 (unbox count)))
         (define local
           (if (string=? chain "")
               (number->string (unbox count))
               (string-append chain "." (number->string (unbox count)))))
         (set-box! out
                   (cons (list (block-label chapter local)
                               (block-node-line node))
                         (unbox out)))
         (number-nodes (block-node-children node)
                       chapter local (box 0) chapters out)]))))

(define (block-number-at o line)
  (define found
    (for/or ([entry (in-list (block-numbers o))])
      (and (= (second entry) line) entry)))
  (and found (first found)))
