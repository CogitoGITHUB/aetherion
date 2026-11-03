#lang racket/base

(require racket/file
         racket/list
         racket/path
         racket/string
         "../checkpoint/checkpoint.rkt"
         "../machine/directories.rkt"
         "../narration/events.rkt"
         "../security/security.rkt"
         "audit.rkt")

(define kept-dir
  (build-path (state-dir) "audit" "kept"))

(define (accept-mark mark)
  (write-mark (hash-set mark 'accepted (utc-now))))

(define (undo-mark root mark)
  (define path-text (hash-ref mark 'path ""))
  (define path (path->complete-path path-text))
  (define checkpoint (hash-ref mark 'checkpoint ""))
  (cond
    [(string=? path-text "")
     (list #f "a mark without a path cannot be undone")]
    [(not (state-changing? "undo"))
     (list #f "the undo is not a change of the tree, and it is refused")]
    [(not (reversible? "undo"))
     (list #f "the undo cannot be taken back, and it is refused")]
    [(not (file-exists? path))
     (list #f (format "there is nothing to undo: ~a is not there" path))]
    [(not (string=? (file-hash path) (hash-ref mark 'hash-after "")))
     (list #f (format "the undo was refused: ~a changed again since the mark, so it is not the change that was marked" path))]
    [else
     (if (string=? (hash-ref mark 'hash-before "") "")
         (undo-new-file root path)
         (undo-known-file root path checkpoint))]))

(define (undo-known-file root path checkpoint)
  (if (git-ok? root "checkout" checkpoint "--" (path-relative path))
      (list (format "the file is back at the checkpoint: ~a" path) #f)
      (list #f (format "the file could not be put back: ~a" path))))

(define (undo-new-file root path)
  (ensure-dir kept-dir)
  (define kept (build-path kept-dir (file-name-from-path path)))
  (copy-file path kept)
  (delete-file path)
  (list (format "the file was taken away and kept: ~a" kept) #f))

(provide kept-dir
         accept-mark
         undo-mark)
