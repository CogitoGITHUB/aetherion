#lang racket/base

(require racket/list
         racket/path
         racket/port
         racket/string
         "../../narration/print-console.rkt"
         "../../narration/narration.rkt"
         "../../machine/directories.rkt"
         "../../commands/commands.rkt"
         "../../commands/tasks.rkt"
         "../../devloop/bake.rkt"
         "../../devloop/last-good.rkt"
         "../../routes/keyboard.rkt"
         "../../routes/keymaps.rkt"
         "../../checkpoint/checkpoint.rkt"
         "../../checkpoint/rollback.rkt"
         "../../machine/stop-switch.rkt"
         "../../send/adapter.rkt"
         "../../send/bundle.rkt"
         "../../send/send.rkt"
         "../../send/opencode-adapter.rkt"
         "../../audit/audit.rkt"
         "../../audit/accept.rkt"
         "../../routes/routes.rkt"
         "../../join/hot-path.rkt"
         "../../join/protocol.rkt"
         "../../notation/document.rkt"
         "../../notation/host.rkt"
         "../live/live.rkt"
         "../plugin-verbs.rkt" "dispatch-git.rkt" "dispatch-agent.rkt" "dispatch-keys.rkt" "dispatch-tasks.rkt" "dispatch-bake.rkt" "dispatch-checkpoint.rkt"
         )

(define (input-is-a-terminal?)
  (terminal-port? (current-input-port)))

(define (edit-session path)
  (define file (path->complete-path path))
  (define journal (journal-path-for file))
  (define session (make-session file journal))
  (ensure-dir (build-path (state-dir) "journal"))
  (if (input-is-a-terminal?)
      (live-session file journal)
      (begin
        (open-run "the editor" (format "editing ~a" file))
        (print-line (answer-line (ask-hot "open" (hasheq 'file (path->string file)
                                                       'journal (path->string journal)))))
        (let ([hot-start (hot-path-start-ms)])
          (when hot-start
            (print-line (format "the hot path's first call took ~a ms" hot-start))))
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

(define (edit-file args)
  (if (null? args)
      (print-line "the editor: edit needs a file")
      (edit-session (car args))))

(define commands
  (hash "edit" edit-file
        "routes" routes-walk
        "task" task-verb
        "tasks" tasks-verb
        "keys" keys-verb
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

(define (command-known? verb)
  (and (hash-has-key? commands verb) #t))

(define (run-verb verb args)
  (define handler (hash-ref commands verb #f))
  (if handler
      (handler args)
      (print-line (format "there is no command named ~a" verb))))

(provide commands
         command-known?
         run-verb)
