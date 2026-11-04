#lang racket/base

(require racket/list
         racket/path
         racket/string
         "../buffer/selection.rkt"
         "../join/protocol.rkt"
         "../join/hot-path.rkt")

(struct session (file journal point selection layer level view-top) #:transparent)

(define (name<? a b)
  (string<? (if (symbol? a) (symbol->string a) a)
            (if (symbol? b) (symbol->string b) b)))

(define (ask session op args)
  (ask-hot op (hash-set (hash-set args 'file (path->string (session-file session)))
                         'journal (path->string (session-journal session)))))

(define (session-text session)
  (define answer (ask session "show" (hasheq)))
  (if (response-ok answer) (hash-ref (response-data answer) 'text "") ""))

(define (answer-line answer)
  (define data (response-data answer))
  (if (response-ok answer)
      (string-join
       (for/list ([key (sort (hash-keys data) name<?)])
         (format "~a=~a" key (hash-ref data key)))
       " ")
      (format "FAIL ~a" (hash-ref data 'what "the hot path refused the request"))))

(define (make-session file journal)
  (session file journal (box 0) (box #f) (box "visual") (box 2) (box 0)))

(define (the-layer session)
  (unbox (session-layer session)))

(define (set-layer! session layer)
  (set-box! (session-layer session) layer)
  layer)

(define (the-level session)
  (unbox (session-level session)))

(define (set-level! session level)
  (set-box! (session-level session) level)
  level)

(define (the-view-top session)
  (unbox (session-view-top session)))

(define (set-view-top! session line)
  (set-box! (session-view-top session) (max 0 line))
  (the-view-top session))

(define (the-point session)
  (unbox (session-point session)))

(define (move-to session at)
  (set-box! (session-point session) at)
  at)

(define (the-selection session)
  (unbox (session-selection session)))

(define (select-from session at)
  (set-box! (session-selection session) (start-region at))
  at)

(define (select-off session)
  (set-box! (session-selection session) #f)
  #f)

(define (selection-text session)
  (define answer
    (region-text (lambda (op args) (ask session op args)) (the-selection session)))
  (if (hash? answer)
      (hash-ref answer 'text "")
      ""))

(provide session make-session session-file session-journal session-point
         session-selection session-layer session-level
         the-point move-to the-selection select-from select-off selection-text
         the-layer set-layer! the-level set-level! the-view-top set-view-top!
         answer-line session-text ask name<?)
