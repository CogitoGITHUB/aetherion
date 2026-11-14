#lang racket/base
;; decision.rkt -- the file type "decision": one decision, written the same way every time.
;; Why: a decision that always names its context, options, choice and consequences can be
;; read years later without asking anyone.
;; Called by: filetypes.rkt (found by scanning filetypes/types/).
(require "_base.rkt")
(provide the-type the-sections)

;; The sections a decision page must hold, in this order.
(define the-sections (list "Context" "Options" "Decision" "Consequences"))

;; The decision type.
(define the-type
  (file-type "decision" "one decision: context, options, decision, consequences"
             (list "title" "chapter" "paragraph" "code" "comment" "answer")))
