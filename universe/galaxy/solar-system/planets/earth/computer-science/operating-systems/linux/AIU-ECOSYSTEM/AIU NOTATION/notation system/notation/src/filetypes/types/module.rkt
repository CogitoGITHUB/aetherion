#lang racket/base
;; module.rkt -- the file type "module": a piece of code explained before it is shown.
;; Why: a module page that states its purpose first can be read without running the code.
;; Called by: filetypes.rkt (found by scanning filetypes/types/).
(require "_base.rkt")
(provide the-type the-sections the-contracts)

;; The sections a module page must hold, in this order.
(define the-sections (list "Purpose" "Code"))

;; The module type.
(define the-type
  (file-type "module" "a purpose, then the code"
             (list "title" "section" "paragraph" "code" "comment")))

;; The contracts of a module page. A rule is checked; a question is only reported.
(define the-contracts
  (list (list 'question "Code" "code" "Does the code do what Purpose says, and nothing more?")
        (list 'rule "Purpose" "paragraph" 'max-words 80)
        (list 'rule "*" "code" 'needs-declaration "language")
        (list 'question "Purpose" "paragraph" "What problem does this module solve, and what does it leave out?")))
