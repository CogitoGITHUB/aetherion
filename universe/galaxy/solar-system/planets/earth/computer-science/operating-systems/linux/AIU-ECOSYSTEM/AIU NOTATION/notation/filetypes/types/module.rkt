#lang racket/base
;; module.rkt -- the file type "module": a piece of code explained before it is shown.
;; Why: a module page that states its purpose first can be read without running the code.
;; Called by: filetypes.rkt (found by scanning filetypes/types/).
(require "_base.rkt")
(provide the-type the-sections)

;; The sections a module page must hold, in this order.
(define the-sections (list "Purpose" "Code"))

;; The module type.
(define the-type
  (file-type "module" "a purpose, then the code"
             (list "title" "chapter" "paragraph" "code" "comment" "answer")))
