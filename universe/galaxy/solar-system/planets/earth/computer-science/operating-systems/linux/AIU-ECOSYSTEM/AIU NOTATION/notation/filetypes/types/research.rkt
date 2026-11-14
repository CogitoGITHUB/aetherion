#lang racket/base
;; research.rkt -- the file type "research": a paper in the usual order.
;; Why: a reader knows where to find the method and the results before opening the file.
;; Called by: filetypes.rkt (found by scanning filetypes/types/).
(require "_base.rkt")
(provide the-type the-sections)

;; The sections a research page must hold, in this order.
(define the-sections
  (list "Abstract" "Introduction" "Methods" "Results" "Discussion" "References"))

;; The research type.
(define the-type
  (file-type "research" "abstract, introduction, methods, results, discussion, references"
             (list "title" "chapter" "paragraph" "code" "comment" "answer")))
