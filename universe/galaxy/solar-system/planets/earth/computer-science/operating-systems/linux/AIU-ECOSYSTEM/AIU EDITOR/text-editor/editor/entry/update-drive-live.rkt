#lang racket/base
;; One job: the live progress lines of the driver, with the seconds since the previous line.
(require racket/system racket/string racket/list racket/file racket/path "update-table.rkt" "update-screen.rkt" "update-evidence.rkt")

;; live-last holds the clock of the last live line.
(define live-last (box (current-inexact-milliseconds)))

;; live prints one line with the seconds since the previous line, so a hang shows its last step.
(define (live msg) (when (live-wanted? msg) (live-print msg)))

;; live-wanted? says whether a live line shows: step lines always, the per key driver lines only when AIU_LIVE is set.
(define (live-wanted? msg)
  (or (getenv "AIU_LIVE")
      (not (regexp-match? #px"^(send key|frame after|send q|wait for exit|editor exited|output drained|driver returned|plain screen|judging|diagnosing|deleting temp|building report)" msg))))

;; live-print writes one live line with the seconds since the previous printed line.
(define (live-print msg) (let ([now (current-inexact-milliseconds)]) (eprintf "  live +~as ~a\n" (real->decimal-string (/ (- now (unbox live-last)) 1000.0) 1) msg) (set-box! live-last now)) (flush-output (current-error-port)))


(provide live-last live live-wanted? live-print)
