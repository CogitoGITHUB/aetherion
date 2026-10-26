#lang racket/base
;; plan.rkt -- the file type "plan": a goal, the steps, and when it is done.
;; Why: a plan that states its goal and its done-when cannot be silently finished or dropped.
;; Called by: filetypes.rkt (found by scanning filetypes/types/).
(require "_base.rkt")
(provide the-type the-sections the-contracts)

;; The sections a plan page must hold, in this order.
(define the-sections (list "Goal" "Steps" "Done when" "Open questions"))

;; The plan type.
(define the-type
  (file-type "plan" "a goal, its steps, when it is done, what is open"
             (list "title" "section" "paragraph" "comment")))

;; The contracts of a plan page. A rule is checked; a question is only reported.
(define the-contracts
  (list (list 'rule "Goal" "paragraph" 'max-words 60)
        (list 'rule "Steps" "paragraph" 'max-words 120)
        (list 'rule "*" "code" 'needs-declaration "language")
        (list 'question "Goal" "paragraph" "Can the goal be stated as one outcome, not an activity?")
        (list 'question "Done when" "paragraph" "Could someone check this without asking the author?")
        (list 'question "Open questions" "paragraph" "Who can answer each open question?")))
