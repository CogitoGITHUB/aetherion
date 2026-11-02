#lang racket/base
;; One job: the pins of the block view. A pin keeps a block on a screen edge when it has scrolled out of the window.
(require "../../commands/commands.rkt")

;; pins holds the pinned boxes, each a list of the block start line, the place top or bottom, hidden and keep-in-focus; unset until first used.
(define pins (box (quote unset)))

;; pin-sel holds the index of the pinned box the pin keys act on.
(define pin-sel (box 0))

;; cur-start holds the start line of the block at the point as of the last drawing.
(define cur-start (box #f))

;; first-start holds the start line of the first block of the page.
(define first-start (box #f))

;; pins-now answers the list of pins and makes the first block the default pin on first use.
(define (pins-now)
  (when (eq? (unbox pins) (quote unset))
    (set-box! pins (if (unbox first-start) (list (list (unbox first-start) "top" #f #t)) (list))))
  (unbox pins))

;; pin-update! replaces the pin at the selected index with the result of f.
(define (pin-update! f)
  (set-box! pins (for/list ([p (in-list (pins-now))] [j (in-naturals)]) (if (= j (unbox pin-sel)) (f p) p))))

;; blockview-command-pin-mode enters the pin layer.
(define (blockview-command-pin-mode session words)
  (pins-now)
  (set-layer! session "pin")
  (cons #t "layer: pin"))

;; blockview-command-pin-add pins the block at the point at the top and selects it.
(define (blockview-command-pin-add session words)
  (define all (pins-now))
  (cond
    [(not (unbox cur-start)) (cons #t "pin: no block")]
    [(ormap (lambda (p) (equal? (car p) (unbox cur-start))) all) (cons #t "pin: already pinned")]
    [else (set-box! pins (append all (list (list (unbox cur-start) "top" #f #f))))
          (set-box! pin-sel (length all))
          (cons #t "pin: added")]))

;; blockview-command-pin-delete deletes the selected pin, the first block too.
(define (blockview-command-pin-delete session words)
  (define all (pins-now))
  (cond
    [(null? all) (cons #t "pin: none")]
    [else
     (define i (min (unbox pin-sel) (- (length all) 1)))
     (set-box! pins (for/list ([p (in-list all)] [j (in-naturals)] #:unless (= j i)) p))
     (set-box! pin-sel (max 0 (min i (- (length all) 2))))
     (cons #t "pin: deleted")]))

;; blockview-command-pin-next selects the next pin.
(define (blockview-command-pin-next session words)
  (define n (length (pins-now)))
  (when (> n 0) (set-box! pin-sel (modulo (add1 (unbox pin-sel)) n)))
  (cons #t "pin: next"))

;; blockview-command-pin-prev selects the previous pin.
(define (blockview-command-pin-prev session words)
  (define n (length (pins-now)))
  (when (> n 0) (set-box! pin-sel (modulo (+ (unbox pin-sel) n -1) n)))
  (cons #t "pin: previous"))

;; blockview-command-pin-top puts the selected pin on the top edge.
(define (blockview-command-pin-top session words)
  (pin-update! (lambda (p) (list (car p) "top" (caddr p) (cadddr p))))
  (cons #t "pin: top"))

;; blockview-command-pin-bottom puts the selected pin on the bottom edge.
(define (blockview-command-pin-bottom session words)
  (pin-update! (lambda (p) (list (car p) "bottom" (caddr p) (cadddr p))))
  (cons #t "pin: bottom"))

;; blockview-command-pin-hide hides or shows the selected pin.
(define (blockview-command-pin-hide session words)
  (pin-update! (lambda (p) (list (car p) (cadr p) (not (caddr p)) (cadddr p))))
  (cons #t "pin: hide toggled"))

;; blockview-command-pin-keep keeps the selected pin visible in focus mode, or hides it there again.
(define (blockview-command-pin-keep session words)
  (pin-update! (lambda (p) (list (car p) (cadr p) (caddr p) (not (cadddr p)))))
  (cons #t "pin: keep in focus toggled"))

;; pin-swap! swaps two pins by index and selects the second place.
(define (pin-swap! a b)
  (define v (list->vector (pins-now)))
  (when (and (<= 0 a) (< a (vector-length v)) (<= 0 b) (< b (vector-length v)))
    (let ([t (vector-ref v a)]) (vector-set! v a (vector-ref v b)) (vector-set! v b t))
    (set-box! pins (vector->list v))
    (set-box! pin-sel b)))

;; blockview-command-pin-earlier moves the selected pin one step earlier in the stack of its edge.
(define (blockview-command-pin-earlier session words)
  (pin-swap! (unbox pin-sel) (- (unbox pin-sel) 1))
  (cons #t "pin: earlier"))

;; blockview-command-pin-later moves the selected pin one step later in the stack of its edge.
(define (blockview-command-pin-later session words)
  (pin-swap! (unbox pin-sel) (+ (unbox pin-sel) 1))
  (cons #t "pin: later"))

(provide pins pin-sel cur-start first-start pins-now pin-update! blockview-command-pin-mode blockview-command-pin-add blockview-command-pin-delete blockview-command-pin-next blockview-command-pin-prev blockview-command-pin-top blockview-command-pin-bottom blockview-command-pin-hide blockview-command-pin-keep pin-swap! blockview-command-pin-earlier blockview-command-pin-later)
