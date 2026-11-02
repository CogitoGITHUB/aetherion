#lang racket/base
;; One job: where the point sits in a page, and how a page reads as text.
;; Registered in plan/package-tree.org; lands with TODO item 21.
;;
;; A page is blocks with byte offsets, and the editor's point is a byte offset,
;; so "which block am I in" is a range test and not a guess. The text these
;; functions answer is the text a person reads: one line per block, one line
;; per fault, and the fault says where it is and what to do.

(require racket/list
         racket/string
         "document.rkt")

;; deepest answers the block of a non-empty list that sits deepest: the
;; innermost block is the one a point inside two blocks belongs to.
(define (deepest blocks)
  (foldl (lambda (b best)
           (if (> (block-depth b) (block-depth best)) b best))
         (car blocks)
         (cdr blocks)))

;; block-at answers the innermost block that holds one byte offset, or #f when
;; the offset is outside every block.
(define (block-at page offset)
  (define inside
    (filter (lambda (b) (and (<= (block-start b) offset) (< offset (block-end b))))
            (page-blocks page)))
  (if (null? inside) #f (deepest inside)))

;; decls-text answers a block's declarations as one text, "keyword: value"
;; pairs separated by commas, or the empty text when the block has none.
(define (decls-text block)
  (string-join
   (for/list ([d (in-list (block-decls block))])
     (format "~a: ~a" (decl-keyword d) (decl-value d)))
   ", "))

;; block-line answers one line for one block: its name, the lines it covers,
;; how deep it sits and its declarations.
(define (block-line block)
  (format "~a~a  lines ~a-~a~a"
          (make-string (* 2 (block-depth block)) #\space)
          (block-name block)
          (block-start-line block)
          (block-end-line block)
          (let ([d (decls-text block)])
            (if (string=? d "") "" (format "  [~a]" d)))))

;; blocks-text answers the whole page as text: one line per block, in document
;; order, then the count.
(define (blocks-text page)
  (string-join
   (append
    (list (format "the page: ~a  blocks: ~a  faults: ~a"
                  (page-file page)
                  (length (page-blocks page))
                  (length (page-faults page))))
    (map block-line (page-blocks page)))
   "\n"))

;; fault-as-text answers one line for one fault: where it is, what is wrong and
;; what to do about it.
(define (fault-as-text fault)
  (format "line ~a: ~a — ~a~a"
          (fault-line fault)
          (fault-what fault)
          (fault-what-to-do fault)
          (if (= (fault-opener-line fault) 0)
              ""
              (format " (the block opens at line ~a)" (fault-opener-line fault)))))

;; faults-text answers the page's faults as text, or says the page is clean.
(define (faults-text page)
  (if (null? (page-faults page))
      (format "the page is clean: ~a blocks, no faults" (length (page-blocks page)))
      (string-join
       (append
        (list (format "faults: ~a of ~a blocks" (length (page-faults page)) (length (page-blocks page))))
        (map fault-as-text (page-faults page)))
       "\n")))

;; block-start-after answers the first block that starts after one byte offset,
;; or #f when the point is past the last block.
(define (block-start-after page offset)
  (define later
    (filter (lambda (b) (> (block-start b) offset)) (page-blocks page)))
  (if (null? later)
      #f
      (foldl (lambda (b best) (if (< (block-start b) (block-start best)) b best))
             (car later)
             (cdr later))))

;; block-start-before answers the last block that starts before one byte
;; offset, or #f when the point is before the first block.
(define (block-start-before page offset)
  (define earlier
    (filter (lambda (b) (< (block-start b) offset)) (page-blocks page)))
  (if (null? earlier)
      #f
      (foldl (lambda (b best) (if (> (block-start b) (block-start best)) b best))
             (car earlier)
             (cdr earlier))))

;; block-closing answers the block that started last at or before one byte
;; offset: the block a "go to the end" belongs to.
(define (block-closing page offset)
  (define started
    (filter (lambda (b) (<= (block-start b) offset)) (page-blocks page)))
  (if (null? started)
      #f
      (foldl (lambda (b best) (if (> (block-start b) (block-start best)) b best))
             (car started)
             (cdr started))))

;; The page as text, for the command table above it.
(provide block-at
         block-line
         blocks-text
         fault-as-text
         faults-text
         block-start-after
         block-start-before
         block-closing)
