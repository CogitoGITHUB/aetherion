#lang racket/base
;; One job: the git verbs of the argv dispatch: git, git-diff and git-history, each asking the shared layer and printing the facts.

(require racket/list racket/path racket/string "../narration/print-console.rkt" "../join/hot-path.rkt" "../join/protocol.rkt")

(provide git-verb git-diff-verb git-history-verb)

;; git-verb asks what Git says about the file, and prints the facts.
;;
;; The shared layer is asked over the seam, and it only reads: no
;; repository, index, branch or worktree is changed, and the editor's
;; buffer is never saved to find out. A file that is not inside a
;; repository is refused by name, and the refusal is printed.
(define (git-verb args)
  (define file (if (null? args) "" (car args)))
  (define path (path->complete-path (if (string=? file "") "untitled" file)))
  (define answer (ask-hot "git" (hasheq 'file (path->string path))))
  (define data (response-data answer))
  (for ([key (in-list (sort (hash-keys data) symbol<?))])
    (print-line (format "~a: ~a" (symbol->string key)
                              (hash-ref data key)))))

;; git-diff-verb asks what Git says differs in the file, and prints the
;; hunks: the place of each hunk on both sides, and the lines that
;; changed with the layer's own marks.
;;
;; The comparison is named in the answer, so the working tree against the
;; index and the index against HEAD are never shown as one thing. The
;; buffer is never saved to find out, and nothing is changed.
(define (git-diff-verb args)
  (define file (if (null? args) "" (car args)))
  (define asked (if (or (null? args) (null? (cdr args))) "unstaged" (cadr args)))
  (define path (path->complete-path (if (string=? file "") "untitled" file)))
  (define answer (ask-hot "git-diff" (hasheq 'file (path->string path)
                                           'comparison asked)))
  (define data (response-data answer))
  (define text (hash-ref data 'git-diff-text ""))
  (if (string=? text "")
      (begin
        (print-line (format "the comparison: ~a"
                            (hash-ref data 'git-diff-comparison "")))
        (print-line (format "the file: ~a" (hash-ref data 'git-diff-file "")))
        (print-line (format "the hunks: ~a" (hash-ref data 'git-diff-hunks "0")))
        (when (not (string=? (hash-ref data 'git-diff-state "") ""))
          (print-line (format "the state: ~a" (hash-ref data 'git-diff-state "")))
          (print-line (format "the why: ~a" (hash-ref data 'git-diff-why "")))))
      (begin
        (print-line (format "the comparison: ~a"
                            (hash-ref data 'git-diff-comparison "")))
        (print-line (format "the file: ~a" (hash-ref data 'git-diff-file "")))
        (print-line (format "the hunks: ~a" (hash-ref data 'git-diff-hunks "0")))
        (for-each print-line (string-split text "\n" #:trim? #f)))))

;; git-history-verb asks what Git says happened in the repository, and
;; prints the commits: the short id, the summary, the author and the
;; date, and the files each commit touched.
;;
;; The layer reads the commits and gives them back; nothing here decides
;; what a commit means, and nothing is changed.
(define (git-history-verb args)
  (define file (if (null? args) "" (car args)))
  (define path (path->complete-path (if (string=? file "") "untitled" file)))
  (define answer (ask-hot "git-history" (hasheq 'file (path->string path))))
  (define data (response-data answer))
  (define text (hash-ref data 'git-history-text ""))
  (if (string=? text "")
      (begin
        (print-line (format "the commits: ~a" (hash-ref data 'git-history-count "0")))
        (when (not (string=? (hash-ref data 'git-history-state "") ""))
          (print-line (format "the state: ~a" (hash-ref data 'git-history-state "")))
          (print-line (format "the why: ~a" (hash-ref data 'git-history-why "")))))
      (begin
        (print-line (format "the commits: ~a" (hash-ref data 'git-history-count "0")))
        (for-each print-line (string-split text "\n" #:trim? #f)))))

