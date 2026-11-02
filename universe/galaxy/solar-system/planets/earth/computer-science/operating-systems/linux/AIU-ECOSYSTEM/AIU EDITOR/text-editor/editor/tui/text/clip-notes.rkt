#lang racket/base
;; clip-notes.rkt. One job: the notifications of copy, cut and paste, one function for each thing that is said.
(require (only-in "../notify/notify.rkt" notify!))

;; clip-note-pieces answers the words for a number of pieces.
(define (clip-note-pieces n) (format "~a piece~a" n (if (= n 1) "" "s")))

;; clip-note-nothing-to-copy says that a copy found nothing to take.
(define (clip-note-nothing-to-copy) (notify! "info" "nothing to copy"))

;; clip-note-copied says how many pieces a copy took.
(define (clip-note-copied n) (notify! "info" (string-append "copied " (clip-note-pieces n))))

;; clip-note-select-first says that a cut needs a selection.
(define (clip-note-select-first) (notify! "info" "select something first: space v"))

;; clip-note-cut says how many pieces a cut took out.
(define (clip-note-cut n) (notify! "info" (string-append "cut " (clip-note-pieces n))))

;; clip-note-nothing-copied says that a paste found no copy in the ring.
(define (clip-note-nothing-copied) (notify! "info" "nothing copied yet"))

;; clip-note-pasted says at how many cursors a paste put its text.
(define (clip-note-pasted k) (notify! "info" (format "pasted at ~a cursor~a" k (if (= k 1) "" "s"))))

(provide clip-note-nothing-to-copy clip-note-copied clip-note-select-first clip-note-cut clip-note-nothing-copied clip-note-pasted)
