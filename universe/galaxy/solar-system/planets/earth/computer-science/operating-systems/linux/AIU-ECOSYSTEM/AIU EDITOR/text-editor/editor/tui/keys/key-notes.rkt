#lang racket/base
;; key-notes.rkt. One job: the notifications of the key routing, one function for each thing that is said.
(require racket/string (only-in "../notify/notify.rkt" notify!))

;; key-note-none says that the keys pressed mean nothing in a layer; names are the key names and label is the layer.
(define (key-note-none names label) (notify! "warn" (format "no key: ~a in ~a" (string-join names " ") label)))

(provide key-note-none)
