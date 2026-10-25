#lang racket/base
;; _base.rkt -- the one door every file type uses to reach the file-type record.
;; Why: the engine lives in "notation system/", so the long path is written once, here.
;; Called by: every module in types/ (the underscore keeps the loader from reading it as a type).
(require (file "../notation system/notation/src/filetypes/type.rkt"))
(provide (all-from-out (file "../notation system/notation/src/filetypes/type.rkt")))
