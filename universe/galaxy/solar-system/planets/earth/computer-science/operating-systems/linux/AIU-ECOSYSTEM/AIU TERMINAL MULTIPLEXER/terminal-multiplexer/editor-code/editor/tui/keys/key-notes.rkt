#lang racket/base
(require racket/string (only-in "../notify/notify.rkt" notify!))

(define (key-note-none names label) (notify! "warn" (format "no key: ~a in ~a" (string-join names " ") label)))

(provide key-note-none)
