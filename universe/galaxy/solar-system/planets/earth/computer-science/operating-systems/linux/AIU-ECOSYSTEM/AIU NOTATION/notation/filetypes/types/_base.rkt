#lang racket/base
;; _base.rkt -- the one door every file type uses to reach the file-type record.
;; Why: the engine file type.rkt sits one folder up, so the path is written once, here.
;; Called by: every module in filetypes/types/ (the underscore keeps the loader from reading it as a type).
(require "../type.rkt")
(provide (all-from-out "../type.rkt"))
