#lang racket/base
(provide (struct-out key-state) initial-key-state key-state-pending-text key-state-pinned-flag route-keys)

(struct key-state (layer pending pinned))

(define space-byte 32)
(define a-byte 97)
(define i-byte 105)
(define q-byte 113)
(define comma-byte 44)
(define z-byte 122)
(define zoxide-pick-bytes (bytes-append (bytes 21) #"let d = (tv zoxide | str trim); if ($d | is-not-empty) { cd $d }\r"))
(define delete-byte 127)

(define (initial-key-state) (key-state "visual" (quote none) #f))
(define (key-state-pending-text state) (if (eq? (key-state-pending state) (quote space)) "space" ""))
(define (key-state-pinned-flag state) (if (key-state-pinned state) "1" "0"))

(define (route-visual state byte)
  (define pinned (key-state-pinned state))
  (cond
    [(eq? (key-state-pending state) (quote space))
     (values (bytes) (cond [(= byte 98) (key-state "buffer" (quote none) pinned)] [(= byte 119) (key-state "pane" (quote none) pinned)] [(= byte 101) (key-state "editor" (quote none) pinned)] [(= byte 115) (key-state "shell" (quote none) pinned)] [(= byte 120) (key-state "pane" (quote float) pinned)] [else (key-state "visual" (quote none) (if (= byte space-byte) (not pinned) pinned))]) #f)]
    [(= byte space-byte) (values (bytes) (key-state "visual" (quote space) pinned) #f)]
    [(= byte i-byte) (values (bytes) (key-state "write" (quote none) pinned) #f)]
    [(= byte z-byte) (values zoxide-pick-bytes state #f)]
    [(= byte q-byte) (values (bytes) state #t)]
    [else (values (bytes) state #f)]))

(define (route-write state byte)
  (define pinned (key-state-pinned state))
  (cond
    [(and (eq? (key-state-pending state) (quote a)) (= byte a-byte))
     (values (bytes delete-byte) (key-state "visual" (quote none) pinned) #f)]
    [(and (eq? (key-state-pending state) (quote blank)) (= byte space-byte))
     (values (bytes byte) (key-state "visual" (quote none) pinned) #f)]
    [(= byte space-byte) (values (bytes byte) (key-state "write" (quote blank) pinned) #f)]
    [(= byte a-byte) (values (bytes byte) (key-state "write" (quote a) pinned) #f)]
    [else (values (bytes byte) (key-state "write" (quote none) pinned) #f)]))

(define (route-app state byte)
  (define pinned (key-state-pinned state))
  (define layer (key-state-layer state))
  (cond
    [(eq? (key-state-pending state) (quote comma))
     (if (= byte comma-byte)
         (values (bytes) (key-state "visual" (quote none) pinned) #f)
         (values (bytes comma-byte byte)
                 (key-state layer (quote none) pinned) #f))]
    [(= byte comma-byte)
     (values (bytes) (key-state layer (quote comma) pinned) #f)]
    [else (values (bytes byte) state #f)]))

(define (route-buffer state byte)
  (if (or (= byte 27) (and (string=? (key-state-layer state) "pane") (or (= byte 120) (= byte 48))))
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
               (if (member (key-state-layer state) (list "buffer" "pane")) (route-buffer state byte) (if (member (key-state-layer state) (list "editor" "shell")) (route-app state byte) (route-write state byte)))))
         (write-bytes forwarded out)
         (values next quit-now?)])))
  (values (get-output-bytes out) final quit?))
