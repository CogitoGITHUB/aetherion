#lang racket/base
(provide (struct-out key-state) initial-key-state key-state-pending-text key-state-pinned-flag route-keys)

(struct key-state (layer pending pinned))

(define space-byte 32)
(define a-byte 97)
(define i-byte 105)
(define q-byte 113)
(define delete-byte 127)

(define (initial-key-state) (key-state "visual" (quote none) #f))
(define (key-state-pending-text state) (if (eq? (key-state-pending state) (quote space)) "space" ""))
(define (key-state-pinned-flag state) (if (key-state-pinned state) "1" "0"))

(define (route-visual state byte)
  (define pinned (key-state-pinned state))
  (cond
    [(eq? (key-state-pending state) (quote space))
     (values (bytes) (cond [(= byte 98) (key-state "buffer" (quote none) pinned)] [(= byte 119) (key-state "pane" (quote none) pinned)] [else (key-state "visual" (quote none) (if (= byte space-byte) (not pinned) pinned))]) #f)]
    [(= byte space-byte) (values (bytes) (key-state "visual" (quote space) pinned) #f)]
    [(= byte i-byte) (values (bytes) (key-state "write" (quote none) pinned) #f)]
    [(= byte q-byte) (values (bytes) state #t)]
    [else (values (bytes) state #f)]))

(define (route-write state byte)
  (define pinned (key-state-pinned state))
  (cond
    [(and (eq? (key-state-pending state) (quote a)) (= byte a-byte))
     (values (bytes delete-byte) (key-state "visual" (quote none) pinned) #f)]
    [(= byte a-byte) (values (bytes byte) (key-state "write" (quote a) pinned) #f)]
    [else (values (bytes byte) (key-state "write" (quote none) pinned) #f)]))

(define (route-buffer state byte)
  (if (= byte 27)
      (values (bytes) (key-state "visual" (quote none) (key-state-pinned state)) #f)
      (values (bytes) state #f)))

(define (route-keys state input)
  (define out (open-output-bytes))
  (define-values (final quit?)
    (for/fold ([state state] [quit? #f]) ([byte (in-bytes input)])
      (cond
        [quit? (values state quit?)]
        [else
         (define-values (forwarded next quit-now?)
           (if (string=? (key-state-layer state) "visual")
               (route-visual state byte)
               (if (member (key-state-layer state) (list "buffer" "pane")) (route-buffer state byte) (route-write state byte))))
         (write-bytes forwarded out)
         (values next quit-now?)])))
  (values (get-output-bytes out) final quit?))
