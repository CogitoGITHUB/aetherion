#lang racket/base
;; journal.rkt -- the file type "journal": dated entries, prose only.
;; Called by: filetypes.rkt (found by scanning filetypes/types/).
(require "_base.rkt")
(provide the-type the-contracts)

;; The journal type.
(define the-type (file-type "journal" "dated entries of prose" (list "title" "section" "paragraph")))

;; The contracts of a journal page. A rule is checked; a question is only reported.
(define the-contracts
  (list (list 'question "*" "title" "Does the title give the date or the topic?")
        (list 'rule "*" "paragraph" 'max-words 200)
        (list 'question "*" "paragraph" "What happened, and what was decided or learned?")))
