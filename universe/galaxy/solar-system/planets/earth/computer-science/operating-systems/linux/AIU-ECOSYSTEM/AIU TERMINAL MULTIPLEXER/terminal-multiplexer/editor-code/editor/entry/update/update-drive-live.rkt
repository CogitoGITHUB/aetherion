#lang racket/base
(require racket/system racket/string racket/list racket/file racket/path "update-table.rkt" "update-screen.rkt" "update-evidence.rkt")

(define live-last (box (current-inexact-milliseconds)))

(define (live msg) (when (live-wanted? msg) (live-print msg)))

(define (live-wanted? msg)
  (or (getenv "AIU_LIVE")
      (not (regexp-match? #px"^(send key|frame after|send q|wait for exit|editor exited|output drained|driver returned|plain screen|judging|diagnosing|deleting temp|building report)" msg))))

(define (live-print msg) (let ([now (current-inexact-milliseconds)]) (eprintf "  live +~as ~a\n" (real->decimal-string (/ (- now (unbox live-last)) 1000.0) 1) msg) (set-box! live-last now)) (flush-output (current-error-port)))


(provide live-last live live-wanted? live-print)
