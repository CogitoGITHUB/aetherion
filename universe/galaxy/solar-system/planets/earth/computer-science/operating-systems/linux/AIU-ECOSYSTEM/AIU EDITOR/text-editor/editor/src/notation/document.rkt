#lang racket/base
;; One job: the page — read the NOTATION-DOCUMENT text the hot path answers,
;; and answer the blocks, the declarations and the faults it holds.
;; Registered in plan/package-tree.org; lands with TODO item 21.
;;
;; The shape is the notation crate's own, frozen in its join export:
;;   NOTATION-DOCUMENT 1
;;   file "<path>"
;;   node block <name> <startLine> <startOffset> <endLine> <endOffset> <depth>
;;   decl <keyword> "<value>" <line> <offset>
;;   error <kind> <line> <offset> <openerLine> "<what>" "<whatToDo>"
;;   end
;; Lines are 1-based and offsets are byte offsets. Version 1 is the only
;; version this reader reads: a document that says anything else is refused by
;; name, never guessed at.

(require racket/list
         racket/string)

;; block is one block of a page: its name, the line and byte where it starts,
;; the line and byte where it ends, how deep it sits, and its declarations.
(struct block (name start-line start end-line end depth decls) #:transparent)

;; decl is one declaration under a block: the keyword, its value and its line.
(struct decl (keyword value line) #:transparent)

;; fault is one fault the parser found: its kind, the line and byte where it
;; is, the block it belongs to, what is wrong and what to do about it.
(struct fault (kind line offset opener-line what what-to-do) #:transparent)

;; page is one parsed page: the file it came from, the version of the document,
;; the blocks in document order and the faults.
(struct page (file version blocks faults) #:transparent)

;; fields-of answers the words of one document line. A quoted word is one word:
;; the quotes are taken off, the spaces inside stay, and a doubled quote is one
;; quote — so a value the notation wrote can be read back exactly.
(define (fields-of line)
  (define len (string-length line))
  (let loop ([i 0] [current ""] [in-quotes? #f] [fields '()])
    (cond
      [(>= i len)
       (reverse (if (string=? current "") fields (cons current fields)))]
      [else
       (define c (string-ref line i))
       (cond
         [in-quotes?
          (cond
            [(char=? c #\")
             (if (and (< (+ i 1) len) (char=? (string-ref line (+ i 1)) #\"))
                 (loop (+ i 2) (string-append current "\"") #t fields)
                 (loop (+ i 1) current #f fields))]
            [else (loop (+ i 1) (string-append current (string c)) #t fields)])]
         [(char=? c #\")
          (loop (+ i 1) current #t fields)]
         [(char=? c #\space)
          (loop (+ i 1) "" #f (if (string=? current "") fields (cons current fields)))]
         [else (loop (+ i 1) (string-append current (string c)) #f fields)])])))

;; number-of answers the number a field holds, and 0 when it holds none: a bad
;; number is the document's fault and the fault is already reported, so the
;; reader does not raise over it.
(define (number-of field)
  (or (string->number field) 0))

;; add-decl answers the block with one more declaration: a declaration belongs
;; to the block the notation printed it under, which is the last block seen.
(define (add-decl blocks decl)
  (cond
    [(null? blocks) blocks]
    [else
     (define top (car blocks))
     (cons (struct-copy block top [decls (append (block-decls top) (list decl))])
           (cdr blocks))]))

;; read-page answers the page a document text holds, or a refusal text when the
;; first line is not a version this reader knows.
(define (read-page text)
  (define lines (string-split text "\n"))
  (define first (if (null? lines) "" (car lines)))
  (cond
    [(not (string=? first "NOTATION-DOCUMENT 1"))
     (format "the page is not a NOTATION-DOCUMENT this editor reads: its first line is ~s" first)]
    [else
     (define rows (cdr lines))
     (define-values (blocks faults file)
       (for/fold ([blocks '()] [faults '()] [file ""]) ([line (in-list rows)])
         (define fields (fields-of line))
         (define tag (if (null? fields) "" (car fields)))
         (cond
           [(and (>= (length fields) 2) (string=? tag "file"))
            (values blocks faults (list-ref fields 1))]
           [(and (>= (length fields) 8) (string=? tag "node")
                 (string=? (list-ref fields 1) "block"))
            (define b (block (list-ref fields 2)
                             (number-of (list-ref fields 3))
                             (number-of (list-ref fields 4))
                             (number-of (list-ref fields 5))
                             (number-of (list-ref fields 6))
                             (number-of (list-ref fields 7))
                             '()))
            (values (cons b blocks) faults file)]
           [(and (>= (length fields) 5) (string=? tag "decl") (not (null? blocks)))
            (define d (decl (list-ref fields 1)
                            (list-ref fields 2)
                            (number-of (list-ref fields 3))))
            (values (add-decl blocks d) faults file)]
           [(and (>= (length fields) 7) (string=? tag "error"))
            (define f (fault (list-ref fields 1)
                             (number-of (list-ref fields 2))
                             (number-of (list-ref fields 3))
                             (number-of (list-ref fields 4))
                             (list-ref fields 5)
                             (list-ref fields 6)))
            (values blocks (cons f faults) file)]
           [else (values blocks faults file)])))
     (page file 1 (reverse blocks) (reverse faults))]))

;; The page, for the areas above it and the gate beside it.
(provide block
         block?
         block-name
         block-start-line
         block-start
         block-end-line
         block-end
         block-depth
         block-decls
         decl
         decl-keyword
         decl-value
         decl-line
         fault
         fault-kind
         fault-line
         fault-offset
         fault-opener-line
         fault-what
         fault-what-to-do
         page
         page?
         page-file
         page-version
         page-blocks
         page-faults
         fields-of
         read-page)
