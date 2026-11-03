#lang racket/base
;; One job: the commands that change the layer, the level and the view line.

(require racket/list
         racket/path
         racket/string
         "../../buffer/selection.rkt"
         "../../join/protocol.rkt"
         "../../join/hot-path.rkt"
         "../../journal/replay.rkt"
         "../../notation/document.rkt"
         "../../notation/host.rkt"
         "../../notation/where.rkt"
         "../session.rkt"
         "../multi-boxes.rkt")

(provide command-mode command-visual-mode command-write-mode command-select-mode command-level-up command-view-up command-view-down)

;; command-mode changes the layer the editor is in: the visual layer goes
;; to the write layer and the write layer goes back to the visual one.
;; The owner's key is a double space in the visual layer and a double tab
;; in the write layer, where a space is a typed space.
(define (command-mode session words)
  (define layer (the-layer session))
  (define next (if (string=? layer "write") "visual" "write"))
  (set-layer! session next)
  (cons #t (format "layer: ~a" next)))

;; command-visual-mode puts the editor in the visual layer, the general
;; mode.
(define (command-visual-mode session words)
  (set-layer! session "visual")
  (cons #t "layer: visual"))

;; command-write-mode puts the editor in the write layer, where the keys
;; are text.
(define (command-write-mode session words)
  (set-layer! session "write")
  (cons #t "layer: write"))

;; command-select-mode puts the editor in the select layer, where the
;; selected text is what the commands act on.
(define (command-select-mode session words)
  (set-layer! session "select")
  (cons #t "layer: select"))

;; command-level-up shows one level more of the editor's own rows.
(define (command-level-up session words)
  (cons #t (format "level: ~a" (set-level! session (min 3 (+ (the-level session) 1))))))

;; command-view-up scrolls the rendered view up one line. The view has a
;; place of its own, so reading a long page never moves the point.
(define (command-view-up session words)
  (cons #t (format "view line: ~a" (set-view-top! session (sub1 (the-view-top session))))))

;; command-view-down scrolls the rendered view down one line.
(define (command-view-down session words)
  (cons #t (format "view line: ~a" (set-view-top! session (add1 (the-view-top session))))))
