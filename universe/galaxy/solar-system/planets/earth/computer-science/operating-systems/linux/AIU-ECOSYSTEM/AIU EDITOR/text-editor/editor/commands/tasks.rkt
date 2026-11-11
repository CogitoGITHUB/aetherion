#lang racket/base

(require racket/file
         racket/list
         racket/runtime-path
         racket/string
         "../narration/print-console-shared.rkt"
         "../commands/commands-shared.rkt")

(define-runtime-path tasks-source "tasks.rkt")

(define dry-run? (make-parameter #f))

(define source-lines (if (file-exists? tasks-source) (file->lines tasks-source) (list)))

(define (task-say session args)
  (string-join args " "))

(define (insert session args)
  (define text (string-join args " "))
  (if (dry-run?)
      (format "would insert: ~a" text)
      (answer-line (ask session "insert" (hasheq 'text text)))))

(define tasks
  (hash "say" task-say
        "insert" insert))

(define task-names
  (sort (hash-keys tasks) string<?))

(define (definition-index name)
  (define wanted (string-append "(define (" name " "))
  (let loop ([lines source-lines] [at 0])
    (cond
      [(null? lines) #f]
      [(string-prefix? (car lines) wanted) at]
      [else (loop (cdr lines) (+ at 1))])))

(define (doc-line-of name)
  (define index (definition-index name))
  (and index
       (let loop ([at (- index 1)] [parts '()])
         (cond
           [(< at 0) (if (null? parts) #f (string-join parts " "))]
           [(string-prefix? (list-ref source-lines at) ";;")
            (loop (- at 1)
                  (cons (string-trim (substring (list-ref source-lines at) 2)) parts))]
           [else (if (null? parts) #f (string-join parts " "))]))))

(define (task-lines)
  (for/list ([name (in-list task-names)])
    (format "~a — ~a" name (or (doc-line-of name) "no doc line"))))

(define (run-task session name args)
  (define task (hash-ref tasks name #f))
  (if task
      (task session args)
      (format "there is no task named ~a; ask for one of: ~a"
              name (string-join task-names ", "))))

(define (run-tasks session groups)
  (for/list ([group (in-list groups)])
    (run-task session (car group) (cdr group))))

(provide dry-run?
         task-say
         insert
         tasks
         task-names
         task-lines
         doc-line-of
         run-task
         run-tasks)
