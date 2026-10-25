#lang racket/base
;; type.rkt -- the file type "book", in its own folder so it can grow modules.
;; Called by: filetypes.rkt (found by scanning file-types/).
(require "../../type.rkt" "blocks.rkt")
(provide the-type)

;; The book type.
(define the-type (file-type "book" "chapters of sections and prose" book-blocks))
