#lang racket/base

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

(provide command-blocks command-block command-check command-next-block command-block-end command-kind)

(define (command-blocks session words)
  (define got (page-of (session-file session) (session-journal session)))
  (cons #t (if (page? got) (blocks-text got) (page-refusal-text got))))

(define (command-block session words)
  (define got (page-of (session-file session) (session-journal session)))
  (if (page? got)
      (let ([b (block-at got (the-point session))])
        (cons #t
              (if b
                  (format "the block: ~a  lines ~a-~a"
                          (block-name b) (block-start-line b) (block-end-line b))
                  "the point is outside every block")))
      (cons #t (page-refusal-text got))))

(define (command-check session words)
  (define got (page-of (session-file session) (session-journal session)))
  (cons #t (if (page? got) (faults-text got) (page-refusal-text got))))

(define (command-next-block session words)
  (define got (page-of (session-file session) (session-journal session)))
  (if (page? got)
      (let ([b (block-start-after got (the-point session))])
        (cond
          [b (move-to session (block-start b))
             (cons #t (format "the block: ~a at line ~a" (block-name b) (block-start-line b)))]
          [else (cons #t "the point is past the last block")]))
      (cons #t (page-refusal-text got))))

(define (command-block-end session words)
  (define got (page-of (session-file session) (session-journal session)))
  (if (page? got)
      (let ([b (block-closing got (the-point session))])
        (cond
          [b (move-to session (block-end b))
             (cons #t (format "the end of ~a is line ~a" (block-name b) (block-end-line b)))]
          [else (cons #t "the point is outside every block")]))
      (cons #t (page-refusal-text got))))

(define (command-kind session words)
  (define name (path->string (session-file session)))
  (cons #t
        (if (string-suffix? name ".aiu")
            "the kind: notation page (.aiu)"
            "the kind: text")))
