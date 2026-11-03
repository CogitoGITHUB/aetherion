#lang racket/base
;; decision.rkt -- the file type "decision": one decision, written the same way every time.
;; Why: a decision that always names its context, options, choice and consequences can be
;; read years later without asking anyone.
;; Called by: filetypes.rkt (found by scanning filetypes/types/).
(require "_base.rkt")
(provide the-type the-sections the-contracts)

;; The sections a decision page must hold, in this order.
(define the-sections (list "Context" "Options" "Decision" "Consequences"))

;; The decision type.
(define the-type
  (file-type "decision" "one decision: context, options, decision, consequences"
             (list "title" "section" "paragraph" "code" "comment" "answer")))

;; The contracts of a decision page. A rule is checked by the checker; a question is only
;; reported, because a person or an AI must judge it.
(define the-contracts
  (list (list 'question "Decision" "paragraph" "Is it one choice, stated so someone can act on it?" "qf9407a")
        (list 'question "Context" "paragraph" "What forces this decision now?" "q552a83")
        (list 'rule "Context" "paragraph" 'max-words 120)
        (list 'rule "Decision" "paragraph" 'max-words 80)
        (list 'rule "*" "code" 'needs-declaration "language")
        (list 'question "Options" "paragraph" "Which option was rejected, and why?" "qe8a03e")
        (list 'question "Consequences" "paragraph" "What gets harder because of this decision?" "q0cb6eb")))
