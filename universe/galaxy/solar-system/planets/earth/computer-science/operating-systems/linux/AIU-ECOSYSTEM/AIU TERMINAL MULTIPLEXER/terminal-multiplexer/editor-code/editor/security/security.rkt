#lang racket/base

(require racket/string)

(define reading-actions
  '("list" "show" "read" "open" "find" "where" "git" "journal" "help"
    "routes" "keys" "tasks" "agent" "audit" "plugin"))

(define changing-actions
  '("send" "new" "new-directory" "rename" "delete" "move" "copy"
    "paste" "cut" "undo" "accept" "agent-write"))

(define reversible-actions
  '("new" "new-directory" "rename" "move" "copy" "paste" "undo"))

(define (state-changing? action)
  (not (member action reading-actions)))

(define (reversible? action)
  (if (member action reversible-actions) #t #f))

(define (checkpoint-needed? action)
  (state-changing? action))

(provide state-changing?
         reversible?
         checkpoint-needed?)
