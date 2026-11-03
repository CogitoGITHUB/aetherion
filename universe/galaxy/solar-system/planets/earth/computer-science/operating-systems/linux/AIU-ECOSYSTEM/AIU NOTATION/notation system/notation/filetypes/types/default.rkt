#lang racket/base
;; default.rkt -- the file type "default": any block is allowed.
;; Called by: filetypes.rkt (found by scanning filetypes/types/).
(require "_base.rkt")
(provide the-type the-contracts)

;; The default type.
(define the-type (file-type "default" "any block is allowed" #f))

;; The contracts of a default page. A rule is checked; a question is only reported.
(define the-contracts
  (list (list 'rule "*" "paragraph" 'max-words 250)
        (list 'rule "*" "code" 'needs-declaration "language")
        (list 'question "*" "title" "Does the title say what the page is about?" "qd2fa77")
        (list 'question "*" "paragraph" "Does the paragraph make one point?" "q94fc72")
        (list 'question "*" "code" "Does the code do what the text around it says?" "qaf213d")))
