#lang racket/base
;; note.rkt -- the file type "note": one idea, a few paragraphs, no sections.
;; Why: a note that cannot grow sections stays one idea; a bigger one is another type.
;; Called by: filetypes.rkt (found by scanning filetypes/types/).
(require "_base.rkt")
(provide the-type the-contracts)

;; The note type.
(define the-type
  (file-type "note" "one idea in a few paragraphs, no sections"
             (list "title" "paragraph" "code" "comment")))

;; The contracts of a note page. A rule is checked; a question is only reported.
(define the-contracts
  (list (list 'rule "*" "paragraph" 'max-words 120)
        (list 'rule "*" "code" 'needs-declaration "language")))
