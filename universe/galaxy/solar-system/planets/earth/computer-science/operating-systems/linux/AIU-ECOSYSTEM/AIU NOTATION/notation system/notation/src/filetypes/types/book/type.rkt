#lang racket/base
;; type.rkt -- the file type "book", in its own folder so it can grow modules.
;; Called by: filetypes.rkt (found by scanning filetypes/types/).
(require "../_base.rkt" "blocks.rkt")
(provide the-type the-contracts)

;; The book type.
(define the-type (file-type "book" "chapters of sections and prose" book-blocks))

;; The contracts of a book page. A rule is checked; a question is only reported.
(define the-contracts
  (list (list 'question "*" "title" "Does the title say what this chapter or section covers?" "qf123ae")
        (list 'rule "*" "paragraph" 'max-words 250)
        (list 'rule "*" "code" 'needs-declaration "language")
        (list 'question "*" "paragraph" "Does this paragraph hold one idea a reader could restate?" "qe995c0")))
