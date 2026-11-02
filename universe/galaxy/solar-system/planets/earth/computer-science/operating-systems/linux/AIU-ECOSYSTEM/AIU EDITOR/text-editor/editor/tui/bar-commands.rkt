#lang racket/base
;; One job: the commands that move, style, hide and focus the bar, added to the command table when this module loads.
(require racket/list
         racket/string
         racket/path
         "../commands/commands.rkt"
         "../commands/lazy-stub.rkt"
         "../routes/keymaps.rkt"
         "box.rkt"
         "tabs.rkt"
         "bar-clock.rkt"
         "bar-git.rkt"
         "bar-state.rkt")


;; put-place! stands the bar at a place and keeps the place for the hide key.
(define (put-place! p)
  (set-box! bar-place p)
  (set-box! bar-saved p))

;; command-bar-mode enters the bar layer.
(define (command-bar-mode session words)
  (set-layer! session "bar")
  (cons #t "layer: bar"))

;; command-bar-level-mode enters the level adjuster.
(define (command-bar-level-mode session words)
  (set-layer! session "bar-level")
  (cons #t "layer: bar-level"))

;; command-bar-place-next moves the bar to the next place and goes round. A
;; hidden bar comes back first.
(define (command-bar-place-next session words)
  (define now (if (string=? (unbox bar-place) "hidden") (unbox bar-saved) (unbox bar-place)))
  (define tail-of (member now bar-places))
  (define next (if (and tail-of (pair? (cdr tail-of))) (cadr tail-of) (car bar-places)))
  (put-place! next)
  (cons #t (format "bar: ~a" next)))

;; command-bar-bottom stands the bar at the bottom.
(define (command-bar-bottom session words) (put-place! "bottom") (cons #t "bar: bottom"))

;; command-bar-top stands the bar at the top.
(define (command-bar-top session words) (put-place! "top") (cons #t "bar: top"))

;; command-bar-left stands the bar on the left.
(define (command-bar-left session words) (put-place! "left") (cons #t "bar: left"))

;; command-bar-right stands the bar on the right.
(define (command-bar-right session words) (put-place! "right") (cons #t "bar: right"))

;; command-bar-sides stands the bar on both sides.
(define (command-bar-sides session words) (put-place! "sides") (cons #t "bar: sides"))

;; command-bar-style switches the side strips between docked and floating.
(define (command-bar-style session words)
  (set-box! bar-style (if (string=? (unbox bar-style) "docked") "floating" "docked"))
  (cons #t (format "bar: ~a" (unbox bar-style))))

;; command-bar-hide hides the bar, or shows it again where it stood.
(define (command-bar-hide session words)
  (cond [(string=? (unbox bar-place) "hidden") (set-box! bar-place (unbox bar-saved))]
        [else (set-box! bar-saved (unbox bar-place))
              (set-box! bar-place "hidden")])
  (cons #t (format "bar: ~a" (unbox bar-place))))

;; command-bar-less hides one part of the bar.
(define (command-bar-less session words)
  (set-box! bar-count (max 0 (sub1 (unbox bar-count))))
  (cons #t (format "bar level: ~a" (unbox bar-count))))

;; command-bar-more shows one more part of the bar.
(define (command-bar-more session words)
  (set-box! bar-count (min (length bar-order) (add1 (unbox bar-count))))
  (cons #t (format "bar level: ~a" (unbox bar-count))))

;; command-focus-toggle turns focus mode on or off: on, the bar, the tabs and the
;; one line mode line are all hidden and the page has the whole screen.
(define (command-focus-toggle session words)
  (set-box! focus-on (not (unbox focus-on)))
  (if (unbox focus-on) (putenv "AIU_FOCUS_COLOURS" "1") (environment-variables-set! (current-environment-variables) #"AIU_FOCUS_COLOURS" #f))
  (cons #t (if (unbox focus-on) "focus: on" "focus: off")))

;; The commands are added to the command table when this module is loaded, so the
;; keys find them and the gate sees the same table the editor does.
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

;; The bar, for the live screen above it.

