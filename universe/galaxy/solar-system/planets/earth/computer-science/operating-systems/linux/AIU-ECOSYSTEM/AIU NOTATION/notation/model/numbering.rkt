#lang racket/base
;; One job: the chapter numbers (1, 1.1, 1.1.2) computed from nesting.
;; A section block takes the next number at its depth and restarts every
;; deeper level. The number is never written, never authored.
;;
;; Who calls it: the reader that draws an outline, and the editor that asks
;; for the number of the heading under the cursor.

(require racket/list
         racket/string
         "nodes.rkt"
         "outline.rkt"
         "properties.rkt"
         "../errors/raise.rkt")

;; Provided so a caller can read the numbers of a document and look one up by
;; the line the heading starts on.
(provide heading-numbers number-at)

;; heading-numbers reads the document and answers the numbers of its
;; headings, in the order the headings appear. Each number is a list of three
;; fields: the number as it is written ("1", "1.1"), the level, and the line
;; the heading starts on.
;;
;; The walk is the tree's own order: a block, then the blocks inside it. A
;; heading nested inside a paragraph is numbered where it stands, so the
;; numbering follows the page and not the block names.
(define (heading-numbers o)
  (define counters (box '()))
  (define out (box '()))
  (for ([node (in-list (outline-nodes o))])
    (walk node 0 counters out))
  (reverse (unbox out)))

(define (walk node depth counters out)
  (when (block-node? node)
    (define inner
      (if (eq? (block-node-name node) (quote section))
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

;; Take the next number at this level and restart every deeper level.
(define (take-number counters level)
  (define index (sub1 level))
  (define grown
    (if (> (length counters) index)
      (append counters '())
      (append counters (make-list (- (add1 index) (length counters)) 0))))
  (define bumped (append grown '()))
  (set! bumped (list-set bumped index (add1 (list-ref bumped index))))
  ;; Every deeper level restarts, because a new heading at this level puts the
  ;; headings under it back at their first number.
  (take bumped (add1 index)))

;; The number as it is written: the counters up to this level, joined with a dot.
(define (number-text counters level)
  (string-join (map number->string (take counters level)) "."))

;; number-at answers the number of the heading that starts on this line, or #f
;; when the line holds no heading. A caller that holds one node asks this for
;; the line that node is on.
(define (number-at o line)
  (define found (for/or ([entry (in-list (heading-numbers o))])
                  (and (= (third entry) line) entry)))
  (and found (first found)))

