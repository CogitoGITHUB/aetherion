#lang racket/base
;; One job: ask the hot path for a page and answer it, or answer why not.
;; Registered in plan/package-tree.org; lands with TODO item 21.
;;
;; The engine is the notation crate, linked into the hot path: one request
;; across the existing seam, no second program and no environment variable.
;; The text that is parsed is the text as it stands — the saved file with the
;; journal's unsaved edits on top — so the page a person is editing is the page
;; the commands answer about.

(require racket/path
         racket/string
         "../join/hot-path.rkt"
         "../join/protocol.rkt"
         "document.rkt")

;; refusal is what a page that cannot be read answers: the kind, what is wrong
;; and what to do, in one text a person can read and act on.
(struct page-refusal (text) #:transparent)

;; answer-data answers one member of the answer the hot path gave, or the empty
;; text when the member is not there.
(define (answer-data answer name)
  (hash-ref (response-data answer) name ""))

;; page-of answers the page of one file as it stands, or a refusal when the
;; seam refuses or the document is a version this editor does not read.
(define (page-of file journal)
  (define answer
    (ask-hot "notation" (hasheq 'file (path->string file)
                                'journal (path->string journal))))
  (cond
    [(response-ok answer)
     (define got (read-page (answer-data answer 'document)))
     (if (page? got)
         got
         (page-refusal (format "the page cannot be read: ~a" got)))]
    [else
     (page-refusal (format "~a: ~a — ~a"
                      (answer-data answer 'kind)
                      (answer-data answer 'what)
                      (answer-data answer 'what_to_do)))]))

;; page-answer? answers whether the answer is a page rather than a refusal.
(define (page-answer? answer)
  (page? answer))

;; The seam call, for the areas above it. refusal-text is the struct's own
;; accessor, so a refusal always prints the one text it was built with.
(provide page-refusal
         page-refusal-text
         page-of
         page-answer?)
