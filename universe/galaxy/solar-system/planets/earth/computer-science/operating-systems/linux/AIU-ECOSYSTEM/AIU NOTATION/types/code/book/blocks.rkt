#lang racket/base
;; blocks.rkt -- the block names a book page may use (a module of the book type).
;; Called by: type.rkt in this folder.
(provide book-blocks)

;; The block names a book may use.
(define book-blocks (list "title" "section" "paragraph" "code" "comment"))
