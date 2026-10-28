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

;; render-of answers the page as a person reads it: the notation's plain
;; render of the text as it stands, so the block markers are gone and the
;; content stays. It is what the view shows and the write layer does not.
(define (render-of file journal)
  (define answer
    (ask-hot "notation-render" (hasheq 'file (path->string file)
                                       'journal (path->string journal))))
  (if (response-ok answer)
      (answer-data answer 'text)
      (format "~a: ~a — ~a"
              (answer-data answer 'kind)
              (answer-data answer 'what)
              (answer-data answer 'what_to_do))))

;; page-answer? answers whether the answer is a page rather than a refusal.
(define (page-answer? answer)
  (page? answer))

;; view-of answers the page the way the notation's own view draws it: the
;; boxes and colours the `notation view` command prints, so the editor's view
;; and tv's preview are one page. A page the view cannot draw answers the
;; reason in one line, so the view never goes blank without saying why.
(define (view-of file journal width)
  (define answer
    (ask-hot "notation-view" (hasheq 'file (path->string file)
                                     'journal (path->string journal)
                                     'width (number->string width))))
  (if (response-ok answer)
      (hash-ref (response-data answer) 'text "")
      (format "~a: ~a — ~a"
              (answer-data answer 'kind)
              (answer-data answer 'what)
              (answer-data answer 'what_to_do))))

;; The seam call, for the areas above it. refusal-text is the struct's own
;; accessor, so a refusal always prints the one text it was built with.
(provide page-refusal
         page-refusal-text
         page-of
         render-of
         view-of
         page-answer?)
