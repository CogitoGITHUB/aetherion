#lang racket/base
;; One job: the commands that read the notation page - blocks, block, check, next-block, block-end and kind.

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

;; command-blocks answers the blocks of the page the session edits, one line
;; each: the name, the lines it covers and its declarations. It is the page as
;; a person reads it, and it is read through the notation engine.
(define (command-blocks session words)
  (define got (page-of (session-file session) (session-journal session)))
  (cons #t (if (page? got) (blocks-text got) (page-refusal-text got))))

;; command-block answers the block the point sits in: the innermost one, so a
;; point inside a section's title answers the title and not the section.
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

;; command-check answers the faults of the page: where each one is, what is
;; wrong and what to do about it. A page with no fault says so.
(define (command-check session words)
  (define got (page-of (session-file session) (session-journal session)))
  (cons #t (if (page? got) (faults-text got) (page-refusal-text got))))

;; command-next-block moves the point to the start of the next block, and says
;; where it landed.
(define (command-next-block session words)
  (define got (page-of (session-file session) (session-journal session)))
  (if (page? got)
      (let ([b (block-start-after got (the-point session))])
        (cond
          [b (move-to session (block-start b))
             (cons #t (format "the block: ~a at line ~a" (block-name b) (block-start-line b)))]
          [else (cons #t "the point is past the last block")]))
      (cons #t (page-refusal-text got))))

;; command-block-end moves the point to the end of the block it is in, so a
;; person can see where the block closes.
(define (command-block-end session words)
  (define got (page-of (session-file session) (session-journal session)))
  (if (page? got)
      (let ([b (block-closing got (the-point session))])
        (cond
          [b (move-to session (block-end b))
             (cons #t (format "the end of ~a is line ~a" (block-name b) (block-end-line b)))]
          [else (cons #t "the point is outside every block")]))
      (cons #t (page-refusal-text got))))

;; command-kind answers what kind of file this session edits: an AIU NOTATION
;; page by its extension, or plain text. The extension is the whole test, and
;; it is the notation format's own.
(define (command-kind session words)
  (define name (path->string (session-file session)))
  (cons #t
        (if (string-suffix? name ".aiu")
            "the kind: notation page (.aiu)"
            "the kind: text")))
