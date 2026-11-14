#lang racket/base
;; default.rkt -- the file type "default": any block is allowed.
;; Called by: filetypes.rkt (found by scanning filetypes/types/).
(require "_base.rkt")
(provide the-type)

;; The default type.
(define the-type (file-type "default" "any block is allowed" #f))
