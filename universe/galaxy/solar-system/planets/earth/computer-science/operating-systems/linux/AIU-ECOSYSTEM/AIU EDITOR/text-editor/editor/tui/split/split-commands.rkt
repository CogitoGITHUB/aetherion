#lang racket/base

(require "../../commands/commands.rkt" "split-state.rkt")

(provide)

(define (pane-answer done message refusal)
  (cons #t (if done message refusal)))

(define (command-pane-mode session words)
  (set-layer! session "pane")
  (cons #t "layer: pane"))

(define (command-pane-split-right session words)
  (split-state-split! "right")
  (cons #t "pane split right"))

(define (command-pane-split-down session words)
  (split-state-split! "down")
  (cons #t "pane split down"))

(define (command-pane-close session words)
  (pane-answer (split-state-close!) "pane closed" "the last pane stays"))

(define (command-pane-focus-left session words) (pane-answer (split-state-focus! "left") "pane left" "no pane on the left"))

(define (command-pane-focus-right session words) (pane-answer (split-state-focus! "right") "pane right" "no pane on the right"))

(define (command-pane-focus-up session words) (pane-answer (split-state-focus! "up") "pane up" "no pane above"))

(define (command-pane-focus-down session words) (pane-answer (split-state-focus! "down") "pane down" "no pane below"))

(define (command-pane-swap-left session words) (pane-answer (split-state-swap! "left") "pane moved left" "no pane on the left"))

(define (command-pane-swap-right session words) (pane-answer (split-state-swap! "right") "pane moved right" "no pane on the right"))

(define (command-pane-swap-up session words) (pane-answer (split-state-swap! "up") "pane moved up" "no pane above"))

(define (command-pane-swap-down session words) (pane-answer (split-state-swap! "down") "pane moved down" "no pane below"))

(define (command-pane-grow-width session words) (pane-answer (split-state-resize! "width" 10) "pane wider" "the pane cannot get wider"))

(define (command-pane-shrink-width session words) (pane-answer (split-state-resize! "width" -10) "pane narrower" "the pane cannot get narrower"))

(define (command-pane-grow-height session words) (pane-answer (split-state-resize! "height" 10) "pane taller" "the pane cannot get taller"))

(define (command-pane-shrink-height session words) (pane-answer (split-state-resize! "height" -10) "pane shorter" "the pane cannot get shorter"))

(define (command-pane-flip session words) (pane-answer (split-state-flip!) "panes mirrored" ""))

(define (command-pane-turn session words) (pane-answer (split-state-turn!) "split turned" ""))

(define (command-pane-equalise session words) (pane-answer (split-state-equalise!) "panes equal" ""))

(hash-set! commands "pane-mode" command-pane-mode)
(hash-set! commands "pane-split-right" command-pane-split-right)
(hash-set! commands "pane-split-down" command-pane-split-down)
(hash-set! commands "pane-close" command-pane-close)
(hash-set! commands "pane-focus-left" command-pane-focus-left)
(hash-set! commands "pane-focus-right" command-pane-focus-right)
(hash-set! commands "pane-focus-up" command-pane-focus-up)
(hash-set! commands "pane-focus-down" command-pane-focus-down)
(hash-set! commands "pane-swap-left" command-pane-swap-left)
(hash-set! commands "pane-swap-right" command-pane-swap-right)
(hash-set! commands "pane-swap-up" command-pane-swap-up)
(hash-set! commands "pane-swap-down" command-pane-swap-down)
(hash-set! commands "pane-grow-width" command-pane-grow-width)
(hash-set! commands "pane-shrink-width" command-pane-shrink-width)
(hash-set! commands "pane-grow-height" command-pane-grow-height)
(hash-set! commands "pane-shrink-height" command-pane-shrink-height)
(hash-set! commands "pane-flip" command-pane-flip)
(hash-set! commands "pane-turn" command-pane-turn)
(hash-set! commands "pane-equalise" command-pane-equalise)
