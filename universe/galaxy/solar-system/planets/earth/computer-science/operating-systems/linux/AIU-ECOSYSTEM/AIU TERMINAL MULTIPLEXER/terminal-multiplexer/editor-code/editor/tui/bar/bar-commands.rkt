#lang racket/base
(require racket/list
         racket/string
         racket/path
         "../../commands/commands.rkt"
         "../../commands/lazy-stub.rkt"
         "../../routes/keymaps.rkt"
         "../float/box.rkt"
         "../tabs/tabs.rkt"
         "bar-clock.rkt"
         "bar-git.rkt"
         "bar-state.rkt")


(define (put-place! p)
  (set-box! bar-place p)
  (set-box! bar-saved p))

(define (command-bar-mode session words)
  (set-layer! session "bar")
  (cons #t "layer: bar"))

(define (command-bar-level-mode session words)
  (set-layer! session "bar-level")
  (cons #t "layer: bar-level"))

(define (command-bar-place-next session words)
  (define now (if (string=? (unbox bar-place) "hidden") (unbox bar-saved) (unbox bar-place)))
  (define tail-of (member now bar-places))
  (define next (if (and tail-of (pair? (cdr tail-of))) (cadr tail-of) (car bar-places)))
  (put-place! next)
  (cons #t (format "bar: ~a" next)))

(define (command-bar-bottom session words) (put-place! "bottom") (cons #t "bar: bottom"))

(define (command-bar-top session words) (put-place! "top") (cons #t "bar: top"))

(define (command-bar-left session words) (put-place! "left") (cons #t "bar: left"))

(define (command-bar-right session words) (put-place! "right") (cons #t "bar: right"))

(define (command-bar-sides session words) (put-place! "sides") (cons #t "bar: sides"))

(define (command-bar-style session words)
  (set-box! bar-style (if (string=? (unbox bar-style) "docked") "floating" "docked"))
  (cons #t (format "bar: ~a" (unbox bar-style))))

(define (command-bar-hide session words)
  (cond [(string=? (unbox bar-place) "hidden") (set-box! bar-place (unbox bar-saved))]
        [else (set-box! bar-saved (unbox bar-place))
              (set-box! bar-place "hidden")])
  (cons #t (format "bar: ~a" (unbox bar-place))))

(define (command-bar-less session words)
  (set-box! bar-count (max 0 (sub1 (unbox bar-count))))
  (cons #t (format "bar level: ~a" (unbox bar-count))))

(define (command-bar-more session words)
  (set-box! bar-count (min (length bar-order) (add1 (unbox bar-count))))
  (cons #t (format "bar level: ~a" (unbox bar-count))))

(define (command-focus-toggle session words)
  (set-box! focus-on (not (unbox focus-on)))
  (if (unbox focus-on) (putenv "AIU_FOCUS_COLOURS" "1") (environment-variables-set! (current-environment-variables) #"AIU_FOCUS_COLOURS" #f))
  (cons #t (if (unbox focus-on) "focus: on" "focus: off")))

(hash-set! commands "bar-mode" command-bar-mode)
(hash-set! commands "bar-level-mode" command-bar-level-mode)
(hash-set! commands "bar-place-next" command-bar-place-next)
(hash-set! commands "bar-bottom" command-bar-bottom)
(hash-set! commands "bar-top" command-bar-top)
(hash-set! commands "bar-left" command-bar-left)
(hash-set! commands "bar-right" command-bar-right)
(hash-set! commands "bar-sides" command-bar-sides)
(hash-set! commands "bar-style" command-bar-style)
(hash-set! commands "bar-hide" command-bar-hide)
(hash-set! commands "bar-less" command-bar-less)
(hash-set! commands "bar-more" command-bar-more)
(hash-set! commands "focus-toggle" command-focus-toggle)


