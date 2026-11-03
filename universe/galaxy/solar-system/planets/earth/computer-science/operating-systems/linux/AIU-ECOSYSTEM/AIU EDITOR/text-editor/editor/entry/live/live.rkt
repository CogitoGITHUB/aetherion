#lang racket/base

(require racket/list
         racket/path racket/port
         racket/path racket/port
         racket/string
         "../../narration/print-console.rkt"
         "../../commands/commands.rkt"
         "../../join/hot-path.rkt"
         "../../join/live-wire.rkt"
         "../../join/protocol.rkt"
         "../../drawing/screen.rkt"
         "../../machine/terminal.rkt"
         "../../routes/keyboard.rkt"
         "../../routes/keymaps.rkt"
         "../../routes/routes.rkt"
         "../../notation/document.rkt"
         "../../notation/host.rkt"
         "../../notation/where.rkt"
         "../../tui/blocks/blockview.rkt" "../../tui/blocks/blocks-edit.rkt" "../../tui/blocks/blocks-view.rkt"
         "../../tui/blocks/blocks-move.rkt"
         "../../tui/float/menu.rkt"
         "../../tui/bar/bar.rkt"
         "../../tui/tabs/tabs.rkt" "../../tui/tabs/tabs-commands.rkt"
         "../../tui/tabs/finder.rkt"
         "../../tui/notify/notify.rkt"
         (only-in "../../tui/float/box.rkt" paint-ready)
         "../../tui/gutter/gutter.rkt"
         "../../tui/gutter/gutterview.rkt"
         (only-in "../../machine/directories.rkt" journal-path-for)
           "live-paint.rkt" "live-keys.rkt")

(define (live-session file journal)
  (tab-show! (path->string file))
  (raw-mode)
  (display "\u001b[?1049h")
  (dynamic-wind
    (lambda () #f)
    (lambda ()
      (wire-start)
      (let next-round ([file file] [journal journal])
        (define session (make-session file journal))
    (trace-session! file)
        (define viewport (box 1))
        (set-layer! session "visual")
        (let ([ln (unbox find-jump)])
          (when ln
            (set-box! find-jump #f)
            (move-to session (line-start-offset (session-text session) ln))))
        (set-box! notify-repaint (lambda () (repaint session viewport)))
        (set-box! edit-hook (lambda () (gutter-stale!) (git-stale!))) (set-box! dirty-hook (lambda () (set-box! unsaved #t)))
        (repaint session viewport)
        (set-box! paint-ready #t)
        (thread (lambda () (repaint session viewport)))
        (key-loop session (current-input-port) viewport)
        (define next (unbox tab-switch))
        (when next
          (set-box! tab-switch #f)
          (next-round (string->path next) (journal-path-for (string->path next))))))
    (lambda ()
      (wire-stop)
      (display "\u001b[?25h")
      (display "\u001b[?1049l")
      (restore-settings))))

(provide live-session)
