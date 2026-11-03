#lang racket/base
(require (only-in "../notify/notify.rkt" notify!))

(define (multi-note-no-line) (notify! "info" "no line there"))

(define (multi-note-cursors n) (notify! "info" (format "cursors: ~a" n)))

(define (multi-note-no-block) (notify! "info" "no block there"))

(define (multi-note-no-word) (notify! "info" "no word here"))

(define (multi-note-no-more-matches) (notify! "info" "no more matches"))

(define (multi-note-only-main) (notify! "info" "only the main cursor is left"))

(define (multi-note-cleared) (notify! "info" "cursors cleared"))

(define (multi-note-cursor-help) (notify! "info" "cursor: t h blocks, arrows lines, j match, v all, r drop, z clear, f write, s select"))

(define (multi-note-select-help) (notify! "info" "select: n s w b arrows text, h t blocks, a p e c k l x o d pick, j v matches, r drop"))

(provide multi-note-no-line multi-note-cursors multi-note-no-block multi-note-no-word multi-note-no-more-matches multi-note-only-main multi-note-cleared multi-note-cursor-help multi-note-select-help)
