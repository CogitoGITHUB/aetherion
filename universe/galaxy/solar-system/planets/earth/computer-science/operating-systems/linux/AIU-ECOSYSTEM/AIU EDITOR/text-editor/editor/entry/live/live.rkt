#lang racket/base
;; One job: the live session — the keys from the terminal, each one
;; routed and run. Registered in plan/package-tree.org; lands with TODO
;; item 6.
;;
;; The loop is action based: it reads the next byte and the read waits
;; for it. There is NO timer anywhere — not for a key, not for a chord,
;; not for a trigger. A key that is the start of a sequence waits for the
;; next key, and the next key is an action.
;;
;; The decoding is the hot path's job (rule 09): the bytes go over the
;; seam and the hot path answers the name of each key and how many
;; bytes it took. The keymaps and the routing are here (rule 13), so
;; this file looks the name up and runs the command the route names.
;;
;; The terminal is given back exactly as it was found, even when the
;; editor was killed: the settings are saved before the terminal goes
;; raw, and the next run gives it back before it goes raw again.

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

;; live-session runs the live session on a file: the terminal goes raw, the keys
;; are read and run, and the terminal is given back when the session ends. A tab
;; key ends one round and names the next file, and the session goes on in the same
;; terminal with that file, so the hot path and the screen stay up while the tabs
;; change. The work not saved yet of every file stays in its own journal.
(define (live-session file journal)
  (tab-show! (path->string file))
  (raw-mode)
  (display "\u001b[?1049h")
  (dynamic-wind
    (lambda () #f)
    (lambda ()
      ;; The hot path is started once here, before the first frame, and kept
      ;; for the whole session: a key asks the child that is already running
      ;; instead of paying a program start for every letter.
      (wire-start)
      (let next-round ([file file] [journal journal])
        (define session (make-session file journal))
    (trace-session! file)
        ;; The viewport is the first text line shown at the top of the screen. It
        ;; changes only when the point leaves the window, so a moving point does
        ;; not drag the page under it.
        (define viewport (box 1))
        ;; The editor opens as a view: the page is shown as a person reads it, and
        ;; nothing is typed until the write layer is asked for with w or i.
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
