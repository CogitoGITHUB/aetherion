#lang racket/base
;; research.rkt -- the file type "research": a paper in the usual order.
;; Why: a reader knows where to find the method and the results before opening the file.
;; Called by: filetypes.rkt (found by scanning filetypes/types/).
(require "_base.rkt")
(provide the-type the-sections the-contracts)

;; The sections a research page must hold, in this order.
(define the-sections
  (list "Abstract" "Introduction" "Methods" "Results" "Discussion" "References"))

;; The research type.
(define the-type
  (file-type "research" "abstract, introduction, methods, results, discussion, references"
             (list "title" "section" "paragraph" "code" "comment")))

;; The contracts of a research page. A rule is checked; a question is only reported.
(define the-contracts
  (list (list 'question "References" "paragraph" "Does every source cited in the text appear here?")
        (list 'question "Introduction" "paragraph" "Does it say why the question matters?")
        (list 'rule "Abstract" "paragraph" 'max-words 200)
        (list 'rule "*" "code" 'needs-declaration "language")
        (list 'question "Abstract" "paragraph" "Does it state the question, the method, the result and a limit?")
        (list 'question "Methods" "paragraph" "Could a reader repeat this from the text alone?")
        (list 'question "Results" "paragraph" "Does every claim point to evidence?")
        (list 'question "Discussion" "paragraph" "What do these results not show?")))
