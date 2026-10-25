#lang racket/base
;; notes.rkt -- the file type "notes": loose notes, any block allowed.
;; Called by: filetypes.rkt (found by scanning this folder).
(require "_base.rkt")
(provide the-type)

;; The notes type.
(define the-type (file-type "notes" "loose notes, any block" #f))
