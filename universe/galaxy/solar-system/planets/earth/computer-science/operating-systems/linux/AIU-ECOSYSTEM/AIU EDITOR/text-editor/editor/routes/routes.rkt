#lang racket/base

(require racket/list
         racket/string
         "keymaps-shared.rkt")

(struct routing (key owner meaning) #:transparent)

(define layers '("multiplexer" "program" "editor" "unclaimed"))

(define named-keys
  '("escape" "return" "tab" "space" "backspace" "delete"
    "up" "down" "left" "right" "home" "end" "pageup" "pagedown"))

(define named-text
  '(("space" . " ")
    ("return" . "\n")))

(define (text-of key)
  (cond
    [(assoc key named-text) (cdr (assoc key named-text))]
    [(member key named-keys) #f]
    [(or (string-prefix? key "C-")
         (string-prefix? key "M-")
         (string-prefix? key "S-")) #f]
    [(= (string-length key) 1) key]
    [else #f]))

(define (route-key key program-claims layer)
  (cond
    [(string=? key reserved-prefix)
     (routing key "multiplexer" #f)]
    [(member key program-claims)
     (routing key "program" #f)]
    [else
     (define bound (binding-of layer key))
     (cond
       [bound (routing key "editor" bound)]
       [(string=? layer "write")
        (define text (text-of key))
        (if text (routing key "editor" text) (routing key "unclaimed" #f))]
       [else (routing key "unclaimed" #f)])]))

(define (route-walk keys program-claims layer)
  (map (lambda (key) (route-key key program-claims layer)) keys))

(define (route-line answer)
  (define key (routing-key answer))
  (define owner (routing-owner answer))
  (define meaning (routing-meaning answer))
  (format "~a -> ~a ~a"
          key
          owner
          (if meaning (format "~a" meaning) "-")))

(define (route-commands)
  (append*
   (for/list ([layer (in-list editor-layers)])
     (for/list ([binding (in-list (keys-of layer))])
       (list layer (car binding) (cadr binding))))))

(define (reserved-prefix-collisions)
  (append*
   (for/list ([layer (in-list editor-layers)])
     (for/list ([binding (in-list (keys-of layer))]
                #:when (string=? (car binding) reserved-prefix))
       (list layer (car binding))))))

(provide routing
         routing-key
         routing-owner
         routing-meaning
         route-key
         route-walk
         route-line
         route-commands
         reserved-prefix-collisions
         reserved-prefix
         keys-of
         text-of
         editor-layers
         layers)
