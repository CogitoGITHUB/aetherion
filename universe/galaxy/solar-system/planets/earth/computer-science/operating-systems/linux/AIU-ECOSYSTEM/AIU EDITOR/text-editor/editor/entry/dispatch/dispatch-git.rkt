#lang racket/base

(require racket/list racket/path racket/string "../../narration/print-console-shared.rkt" "../../join/hot-path-shared.rkt" "../../join/protocol-shared.rkt")

(provide git-verb git-diff-verb git-history-verb)

(define (git-verb args)
  (define file (if (null? args) "" (car args)))
  (define path (path->complete-path (if (string=? file "") "untitled" file)))
  (define answer (ask-hot "git" (hasheq 'file (path->string path))))
  (define data (response-data answer))
  (for ([key (in-list (sort (hash-keys data) symbol<?))])
    (print-line (format "~a: ~a" (symbol->string key)
                              (hash-ref data key)))))

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

