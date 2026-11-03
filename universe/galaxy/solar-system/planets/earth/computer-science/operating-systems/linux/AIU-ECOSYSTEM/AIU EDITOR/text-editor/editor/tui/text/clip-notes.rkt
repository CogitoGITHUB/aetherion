#lang racket/base
(require (only-in "../notify/notify.rkt" notify!))

(define (clip-note-pieces n) (format "~a piece~a" n (if (= n 1) "" "s")))

(define (clip-note-nothing-to-copy) (notify! "info" "nothing to copy"))

(define (clip-note-copied n) (notify! "info" (string-append "copied " (clip-note-pieces n))))

(define (clip-note-select-first) (notify! "info" "select something first: space v"))

(define (clip-note-cut n) (notify! "info" (string-append "cut " (clip-note-pieces n))))

(define (clip-note-nothing-copied) (notify! "info" "nothing copied yet"))

(define (clip-note-pasted k) (notify! "info" (format "pasted at ~a cursor~a" k (if (= k 1) "" "s"))))

(provide clip-note-nothing-to-copy clip-note-copied clip-note-select-first clip-note-cut clip-note-nothing-copied clip-note-pasted)
