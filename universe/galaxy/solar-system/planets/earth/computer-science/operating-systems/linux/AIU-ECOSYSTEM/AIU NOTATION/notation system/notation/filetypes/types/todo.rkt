#lang racket/base
;; todo.rkt -- the file type "todo": a list of tasks, grouped in sections.
;; Called by: filetypes.rkt (found by scanning filetypes/types/).
(require "_base.rkt")
(provide the-type the-contracts)

;; The todo type.
(define the-type (file-type "todo" "tasks grouped in sections" (list "title" "section" "paragraph" "comment" "answer")))

;; The contracts of a todo page. A rule is checked; a question is only reported.
(define the-contracts
  (list (list 'question "*" "title" "Does the title name one group of tasks?" "q8d0b1f")
        (list 'rule "*" "paragraph" 'max-words 40)
        (list 'rule "*" "paragraph" 'max-lines 3)
        (list 'question "*" "paragraph" "Is this one action that can be finished and checked?" "qadd5fe")))
