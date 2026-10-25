#lang racket/base
;; journal.rkt -- the file type "journal": dated entries, prose only.
;; Called by: filetypes.rkt (found by scanning filetypes/types/).
(require "_base.rkt")
(provide the-type)

;; The journal type.
(define the-type (file-type "journal" "dated entries of prose" (list "title" "section" "paragraph")))
