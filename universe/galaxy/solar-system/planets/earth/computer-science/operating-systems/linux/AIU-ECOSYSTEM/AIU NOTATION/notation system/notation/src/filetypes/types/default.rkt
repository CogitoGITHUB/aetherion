#lang racket/base
;; default.rkt -- the file type "default": any block is allowed.
;; Called by: filetypes.rkt (found by scanning filetypes/types/).
(require "_base.rkt")
(provide the-type the-contracts)

;; The default type.
(define the-type (file-type "default" "any block is allowed" #f))

;; The contracts of a default page. A rule is checked; there are no questions.
(define the-contracts
  (list (list 'rule "*" "paragraph" 'max-words 250)
        (list 'rule "*" "code" 'needs-declaration "language")))
