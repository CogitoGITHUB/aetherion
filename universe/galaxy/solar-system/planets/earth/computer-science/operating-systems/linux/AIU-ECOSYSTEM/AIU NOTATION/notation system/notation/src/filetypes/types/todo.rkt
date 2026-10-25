#lang racket/base
;; todo.rkt -- the file type "todo": a list of tasks, grouped in sections.
;; Called by: filetypes.rkt (found by scanning filetypes/types/).
(require "_base.rkt")
(provide the-type)

;; The todo type.
(define the-type (file-type "todo" "tasks grouped in sections" (list "title" "section" "paragraph" "comment")))
