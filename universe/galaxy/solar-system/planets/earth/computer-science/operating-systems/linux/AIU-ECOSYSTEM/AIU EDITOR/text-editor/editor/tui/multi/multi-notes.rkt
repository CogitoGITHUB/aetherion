#lang racket/base
;; multi-notes.rkt. One job: the notifications of multiple cursors and the selection mode, one function for each thing that is said.
(require (only-in "../notify/notify.rkt" notify!))

;; multi-note-no-line says that no line is left for a new cursor.
(define (multi-note-no-line) (notify! "info" "no line there"))

;; multi-note-cursors says how many cursors there are now.
(define (multi-note-cursors n) (notify! "info" (format "cursors: ~a" n)))

;; multi-note-no-block says that no block of the picked kind is there.
(define (multi-note-no-block) (notify! "info" "no block there"))

;; multi-note-no-word says that the point is on no word to match.
(define (multi-note-no-word) (notify! "info" "no word here"))

;; multi-note-no-more-matches says that the word has no further match.
(define (multi-note-no-more-matches) (notify! "info" "no more matches"))

;; multi-note-only-main says that only the main cursor is left.
(define (multi-note-only-main) (notify! "info" "only the main cursor is left"))

;; multi-note-cleared says that the extra cursors are gone.
(define (multi-note-cleared) (notify! "info" "cursors cleared"))

;; multi-note-cursor-help lists the keys of the cursor layer.
(define (multi-note-cursor-help) (notify! "info" "cursor: t h blocks, arrows lines, j match, v all, r drop, z clear, f write, s select"))

;; multi-note-select-help lists the keys of the select layer.
(define (multi-note-select-help) (notify! "info" "select: n s w b arrows text, h t blocks, a p e c k l x o d pick, j v matches, r drop"))

(provide multi-note-no-line multi-note-cursors multi-note-no-block multi-note-no-word multi-note-no-more-matches multi-note-only-main multi-note-cleared multi-note-cursor-help multi-note-select-help)
