#lang racket/base
;; type.rkt -- the shape of one file type.
;; Why: every file type hands the engine the same record, so the engine never needs to
;; know which types exist.
;; Called by: filetypes.rkt and every module in filetypes/types/.
(provide (struct-out file-type))

;; A file type: its name, a one-line description, and the block names a page of this
;; type may use (a list of names, or #f for any block).
(struct file-type (name description allowed-blocks) #:transparent)
