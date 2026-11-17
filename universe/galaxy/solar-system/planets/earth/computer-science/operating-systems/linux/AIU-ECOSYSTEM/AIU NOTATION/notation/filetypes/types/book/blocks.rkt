#lang racket/base
;; blocks.rkt -- the block names a book page may use (a module of the book type).
;; Called by: type.rkt in this folder.
(provide book-blocks)

;; The block names a book may use.
(define book-blocks (list "title" "chapter" "paragraph" "code" "comment" "answer" "cover" "title-page" "copyright" "preface" "contents" "figure" "footnote" "reference" "bibliography" "index" "volume" "list" "steps" "definition" "example" "exercise" "space" "formula" "callout" "pin" "part" "appendix" "glossary" "abstract" "dedication" "epigraph" "acknowledgments" "claim" "evidence" "hypothesis" "remark" "quote" "aside" "link"))
