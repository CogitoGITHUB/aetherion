#lang racket/base

(require json
         racket/list
         racket/string)

(define exit-ok 0)

(define exit-refusal 2)

(define exit-cannot-run 3)

(define program-name "aiu-editor")

(define envelope-version "1")

(struct document (kind ok data refusal events) #:transparent)

(define (make-document kind ok data refusal events)
  (document kind ok data refusal events))

(define (refusal-document kind rule message)
  (make-document kind #f #f (hash 'rule rule 'message message) '()))

(define (document-json doc)
  (hash 'program program-name
        'version envelope-version
        'kind (document-kind doc)
        'ok (and (document-ok doc) #t)
        'data (or (document-data doc) '())
        'refusal (or (document-refusal doc) '())
        'events (or (document-events doc) '())))

(define (document-line doc)
  (define out (open-output-string))
  (write-json (document-json doc) out)
  (get-output-string out))

(provide exit-ok
         exit-refusal
         exit-cannot-run
         program-name
         envelope-version
         document
         document-kind
         document-ok
         document-data
         document-refusal
         document-events
         make-document
         refusal-document
         document-json
         document-line)
