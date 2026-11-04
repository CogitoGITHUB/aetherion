#lang racket/base

(require racket/list
         racket/string
         "document-shared.rkt")

(define (deepest blocks)
  (foldl (lambda (b best)
           (if (> (block-depth b) (block-depth best)) b best))
         (car blocks)
         (cdr blocks)))

(define (block-at page offset)
  (define inside
    (filter (lambda (b) (and (<= (block-start b) offset) (< offset (block-end b))))
            (page-blocks page)))
  (if (null? inside) #f (deepest inside)))

(define (decls-text block)
  (string-join
   (for/list ([d (in-list (block-decls block))])
     (format "~a: ~a" (decl-keyword d) (decl-value d)))
   ", "))

(define (block-line block)
  (format "~a~a  lines ~a-~a~a"
          (make-string (* 2 (block-depth block)) #\space)
          (block-name block)
          (block-start-line block)
          (block-end-line block)
          (let ([d (decls-text block)])
            (if (string=? d "") "" (format "  [~a]" d)))))

(define (blocks-text page)
  (string-join
   (append
    (list (format "the page: ~a  blocks: ~a  faults: ~a"
                  (page-file page)
                  (length (page-blocks page))
                  (length (page-faults page))))
    (map block-line (page-blocks page)))
   "\n"))

(define (fault-as-text fault)
  (format "line ~a: ~a — ~a~a"
          (fault-line fault)
          (fault-what fault)
          (fault-what-to-do fault)
          (if (= (fault-opener-line fault) 0)
              ""
              (format " (the block opens at line ~a)" (fault-opener-line fault)))))

(define (faults-text page)
  (if (null? (page-faults page))
      (format "the page is clean: ~a blocks, no faults" (length (page-blocks page)))
      (string-join
       (append
        (list (format "faults: ~a of ~a blocks" (length (page-faults page)) (length (page-blocks page))))
        (map fault-as-text (page-faults page)))
       "\n")))

(define (block-start-after page offset)
  (define later
    (filter (lambda (b) (> (block-start b) offset)) (page-blocks page)))
  (if (null? later)
      #f
      (foldl (lambda (b best) (if (< (block-start b) (block-start best)) b best))
             (car later)
             (cdr later))))

(define (block-start-before page offset)
  (define earlier
    (filter (lambda (b) (< (block-start b) offset)) (page-blocks page)))
  (if (null? earlier)
      #f
      (foldl (lambda (b best) (if (> (block-start b) (block-start best)) b best))
             (car earlier)
             (cdr earlier))))

(define (block-closing page offset)
  (define started
    (filter (lambda (b) (<= (block-start b) offset)) (page-blocks page)))
  (if (null? started)
      #f
      (foldl (lambda (b best) (if (> (block-start b) (block-start best)) b best))
             (car started)
             (cdr started))))

(provide block-at
         block-line
         blocks-text
         fault-as-text
         faults-text
         block-start-after
         block-start-before
         block-closing)
