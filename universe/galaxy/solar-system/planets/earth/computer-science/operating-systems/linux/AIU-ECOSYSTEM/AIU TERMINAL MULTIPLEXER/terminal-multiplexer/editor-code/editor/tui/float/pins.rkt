#lang racket/base
(require "../../commands/commands.rkt")

(define pins (box (quote unset)))

(define pin-sel (box 0))

(define cur-start (box #f))

(define first-start (box #f))

(define (pins-now)
  (when (eq? (unbox pins) (quote unset))
    (set-box! pins (if (unbox first-start) (list (list (unbox first-start) "top" #f #t)) (list))))
  (unbox pins))

(define (pin-update! f)
  (set-box! pins (for/list ([p (in-list (pins-now))] [j (in-naturals)]) (if (= j (unbox pin-sel)) (f p) p))))

(define (blockview-command-pin-mode session words)
  (pins-now)
  (set-layer! session "pin")
  (cons #t "layer: pin"))

(define (blockview-command-pin-add session words)
  (define all (pins-now))
  (cond
    [(not (unbox cur-start)) (cons #t "pin: no block")]
    [(ormap (lambda (p) (equal? (car p) (unbox cur-start))) all) (cons #t "pin: already pinned")]
    [else (set-box! pins (append all (list (list (unbox cur-start) "top" #f #f))))
          (set-box! pin-sel (length all))
          (cons #t "pin: added")]))

(define (blockview-command-pin-delete session words)
  (define all (pins-now))
  (cond
    [(null? all) (cons #t "pin: none")]
    [else
     (define i (min (unbox pin-sel) (- (length all) 1)))
     (set-box! pins (for/list ([p (in-list all)] [j (in-naturals)] #:unless (= j i)) p))
     (set-box! pin-sel (max 0 (min i (- (length all) 2))))
     (cons #t "pin: deleted")]))

(define (blockview-command-pin-next session words)
  (define n (length (pins-now)))
  (when (> n 0) (set-box! pin-sel (modulo (add1 (unbox pin-sel)) n)))
  (cons #t "pin: next"))

(define (blockview-command-pin-prev session words)
  (define n (length (pins-now)))
  (when (> n 0) (set-box! pin-sel (modulo (+ (unbox pin-sel) n -1) n)))
  (cons #t "pin: previous"))

(define (blockview-command-pin-top session words)
  (pin-update! (lambda (p) (list (car p) "top" (caddr p) (cadddr p))))
  (cons #t "pin: top"))

(define (blockview-command-pin-bottom session words)
  (pin-update! (lambda (p) (list (car p) "bottom" (caddr p) (cadddr p))))
  (cons #t "pin: bottom"))

(define (blockview-command-pin-hide session words)
  (pin-update! (lambda (p) (list (car p) (cadr p) (not (caddr p)) (cadddr p))))
  (cons #t "pin: hide toggled"))

(define (blockview-command-pin-keep session words)
  (pin-update! (lambda (p) (list (car p) (cadr p) (caddr p) (not (cadddr p)))))
  (cons #t "pin: keep in focus toggled"))

(define (pin-swap! a b)
  (define v (list->vector (pins-now)))
  (when (and (<= 0 a) (< a (vector-length v)) (<= 0 b) (< b (vector-length v)))
    (let ([t (vector-ref v a)]) (vector-set! v a (vector-ref v b)) (vector-set! v b t))
    (set-box! pins (vector->list v))
    (set-box! pin-sel b)))

(define (blockview-command-pin-earlier session words)
  (pin-swap! (unbox pin-sel) (- (unbox pin-sel) 1))
  (cons #t "pin: earlier"))

(define (blockview-command-pin-later session words)
  (pin-swap! (unbox pin-sel) (+ (unbox pin-sel) 1))
  (cons #t "pin: later"))

(provide pins pin-sel cur-start first-start pins-now pin-update! blockview-command-pin-mode blockview-command-pin-add blockview-command-pin-delete blockview-command-pin-next blockview-command-pin-prev blockview-command-pin-top blockview-command-pin-bottom blockview-command-pin-hide blockview-command-pin-keep pin-swap! blockview-command-pin-earlier blockview-command-pin-later)
