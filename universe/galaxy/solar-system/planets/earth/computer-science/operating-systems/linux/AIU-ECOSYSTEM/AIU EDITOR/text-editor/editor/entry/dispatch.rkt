#lang racket/base
;; One job: the argv dispatch — one name, one function. The name is the
;; verb the user typed; the function is what it does. The session it runs
;; reads one command per line from the standard input, and every answer is
;; printed in the one printer, so the run reads in one voice.
;;
;; The order of this file is the order Racket reads it: the table comes
;; after the functions it names, so it can be built when the file loads.

(require racket/list
         racket/path
         racket/port
         racket/string
         "../narration/print-console.rkt"
         "../narration/narration.rkt"
         "../machine/directories.rkt"
         "../commands/commands.rkt"
         "../commands/tasks.rkt"
         "../devloop/bake.rkt"
         "../devloop/last-good.rkt"
         "../tui/dashboard.rkt"
         "../routes/keyboard.rkt"
         "../routes/keymaps.rkt"
         "../checkpoint/checkpoint.rkt"
         "../checkpoint/rollback.rkt"
         "../machine/stop-switch.rkt"
         "../send/adapter.rkt"
         "../send/bundle.rkt"
         "../send/send.rkt"
         "../send/opencode-adapter.rkt"
         "../audit/audit.rkt"
         "../audit/accept.rkt"
         "../routes/routes.rkt"
         "../join/hot-path.rkt"
         "../join/protocol.rkt"
         "../notation/document.rkt"
         "../notation/host.rkt"
         "live.rkt"
         "plugin-verbs.rkt" "dispatch-git.rkt" "dispatch-agent.rkt" "dispatch-keys.rkt" "dispatch-tasks.rkt" "dispatch-bake.rkt" "dispatch-checkpoint.rkt"
         )

;; input-is-a-terminal? answers whether the standard input is a
;; terminal, and not a pipe. A terminal means the live session: the keys
;; are read one at a time. A pipe means the scripted session: one
;; command per line, so every proof that drives the editor with a pipe
;; keeps working.
(define (input-is-a-terminal?)
  (terminal-port? (current-input-port)))

;; edit-session opens the file, then reads one command per line until the
;; session ends or the input ends. Every answer goes through the one
;; printer.
(define (edit-session path)
  (define file (path->complete-path path))
  (define journal (journal-path-for file))
  (define session (make-session file journal))
  ;; the journal's directory is made before the first edit: the hot path
  ;; writes there, and it must not have to create a directory to save work
  (ensure-dir (build-path (state-dir) "journal"))
  (if (input-is-a-terminal?)
      (live-session file journal)
      (begin
        (open-run "the editor" (format "editing ~a" file))
        (print-line (answer-line (ask-hot "open" (hasheq 'file (path->string file)
                                                       'journal (path->string journal)))))
        ;; the hot path's start is printed with the first answer: the
        ;; hot path is a child, and its start is the time its first
        ;; question took
        (let ([hot-start (hot-path-start-ms)])
          (when hot-start
            (print-line (format "the hot path's first call took ~a ms" hot-start))))
        ;; An AIU NOTATION page says what it is the moment it opens: how many
        ;; blocks it holds and how many faults the parser found. The page is
        ;; read through the same engine the commands use, so the line cannot
        ;; disagree with them.
        (when (string-suffix? (path->string file) ".aiu")
          (define got (page-of file journal))
          (print-line
           (if (page? got)
               (format "the page: ~a blocks, ~a faults (commands: blocks, block, check, next-block, prev-block, block-end)"
                       (length (page-blocks got))
                       (length (page-faults got)))
               (page-refusal-text got))))
        (let loop ()
          (define line (read-line (current-input-port)))
          (unless (eof-object? line)
            (define answer (run-command session line))
            (define text (cdr answer))
            (unless (string=? text "") (print-line text))
            (when (car answer) (loop)))))))

;; edit-file opens the file the user named and runs the editing session.
(define (edit-file args)
  (if (null? args)
      (print-line "the editor: edit needs a file")
      (edit-session (car args))))

;; commands is the table: one name, one function.
(define commands
  (hash "edit" edit-file
        "routes" routes-walk
        "task" task-verb
        "tasks" tasks-verb
        "keys" keys-verb
        "dashboard" dashboard-verb
        "git" git-verb
        "git-diff" git-diff-verb
        "git-history" git-history-verb
        "bake" bake-verb
        "send" send-verb
        "agent" agent-verb
        "audit" audit-verb
        "audit-accept" audit-accept-verb
        "audit-undo" audit-undo-verb
        "permit" permit-verb
        "agent-end" agent-end-verb
        "checkpoint" checkpoint-verb
        "rollback" rollback-verb
        "stop" stop-verb
        "plugin" plugin-verb
        "plugin-register" plugin-register-verb
        "plugin-install" plugin-install-verb
        "plugin-call" plugin-call-verb))

;; command-known? answers whether the table holds the name.
(define (command-known? verb)
  (and (hash-has-key? commands verb) #t))

;; run-verb runs the verb with its arguments.
(define (run-verb verb args)
  (define handler (hash-ref commands verb #f))
  (if handler
      (handler args)
      (print-line (format "there is no command named ~a" verb))))

;; The argv dispatch, for the entry above it.
(provide commands
         command-known?
         run-verb)
