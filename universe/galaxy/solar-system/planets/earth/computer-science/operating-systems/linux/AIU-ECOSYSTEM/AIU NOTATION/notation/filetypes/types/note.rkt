#lang racket/base
;; note.rkt -- the file type "note": one idea, a few paragraphs, no sections.
;; Why: a note that cannot grow sections stays one idea; a bigger one is another type.
;; Called by: filetypes.rkt (found by scanning filetypes/types/).
(require "_base.rkt")
(provide the-type)

;; The note type.
(define the-type
  (file-type "note" "one idea in a few paragraphs, no sections"
             (list "title" "paragraph" "code" "comment" "answer")))
