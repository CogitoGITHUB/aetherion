#lang racket/base

(require racket/list
         racket/path
         racket/string
         "../../buffer/selection-shared.rkt"
         "../../join/protocol-shared.rkt"
         "../../join/hot-path-shared.rkt"
         "../../journal/replay-shared.rkt"
         "../../bridge/document-shared.rkt"
         "../../bridge/host-shared.rkt"
         "../../bridge/where-shared.rkt"
         "../session-shared.rkt"
         "../multi-boxes-shared.rkt")

(provide command-mode command-visual-mode command-write-mode command-select-mode command-level-up command-view-up command-view-down)

(define (command-mode session words)
  (define layer (the-layer session))
  (define next (if (string=? layer "write") "visual" "write"))
  (set-layer! session next)
  (cons #t (format "layer: ~a" next)))

(define (command-visual-mode session words)
  (set-layer! session "visual")
  (cons #t "layer: visual"))

(define (command-write-mode session words)
  (set-layer! session "write")
  (cons #t "layer: write"))

(define (command-select-mode session words)
  (set-layer! session "select")
  (cons #t "layer: select"))

(define (command-level-up session words)
  (cons #t (format "level: ~a" (set-level! session (min 3 (+ (the-level session) 1))))))

(define (command-view-up session words)
  (cons #t (format "view line: ~a" (set-view-top! session (sub1 (the-view-top session))))))

(define (command-view-down session words)
  (cons #t (format "view line: ~a" (set-view-top! session (add1 (the-view-top session))))))
