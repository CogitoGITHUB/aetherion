#lang racket/base
;; plan.rkt -- the file type "plan": a goal, the steps, and when it is done.
;; Why: a plan that states its goal and its done-when cannot be silently finished or dropped.
;; Called by: filetypes.rkt (found by scanning filetypes/types/).
(require "_base.rkt")
(provide the-type the-sections)

;; The sections a plan page must hold, in this order.
(define the-sections (list "Goal" "Steps" "Done when" "Open questions"))

;; The plan type.
(define the-type
  (file-type "plan" "a goal, its steps, when it is done, what is open"
             (list "title" "chapter" "paragraph" "comment" "answer")))
