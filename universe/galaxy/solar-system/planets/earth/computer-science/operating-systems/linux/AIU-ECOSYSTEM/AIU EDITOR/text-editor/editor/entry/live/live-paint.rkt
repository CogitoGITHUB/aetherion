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
         "../../tui/tabs/tabs.rkt"
         "../../tui/tabs/finder.rkt"
         "../../tui/notify/notify.rkt"
         (only-in "../../tui/float/box.rkt" paint-ready)
         "../../tui/gutter/gutter.rkt"
         "../../tui/gutter/gutterview.rkt"
         (only-in "../../machine/directories.rkt" journal-path-for))

(require (only-in "../../tui/bar/bar-state.rkt" title-rows) (only-in "../../tui/float/pins.rkt" pins-now first-start cur-start))

(provide repaint page-view pending-keys viewport-top live-multi-overlay)

(define (page-view session raw width)
  (define name (path->string (session-file session)))
  (if (string-suffix? name ".aiu")
      (drawn-view session raw width)
      raw))

(define (title-box-of session width)
  (define name (path->string (session-file session)))
  (define p (and (string-suffix? name ".aiu") (unbox first-start) (pair? (pins-now)) (car (pins-now))))
  (cond
    [(and p (not (caddr p)) (not (multi-raw? session)) (not (equal? (unbox cur-start) (unbox first-start))))
     (define ls (string-split (view-of (session-file session) (session-journal session) width) "\n" #:trim? #f))
     (define end (for/first ([l (in-list ls)] [i (in-naturals)] #:when (regexp-match? (regexp "╰") l)) i))
     (if (and (pair? ls) end (regexp-match? (regexp "title") (car ls)))
         (for/list ([l (in-list ls)] [i (in-range (add1 end))]) l)
         (list))]
    [else (list)]))

(define paint-lock (make-semaphore 1))

(define pending-keys (box (list)))

(define (repaint session viewport)
  (call-with-semaphore paint-lock (lambda () (repaint-now session viewport))))

(define (repaint-now session viewport)
  (define-values (full-width full-height) (terminal-size))
  (set-box! title-rows (title-box-of session full-width))
  (define plan
    (bar-plan-of session (unbox pending-keys) full-width full-height
                 void))
  (define gut? (and (string-suffix? (path->string (session-file session)) ".aiu")))
  (when (and gut? (not (unbox unsaved))) (gutter-refresh-maybe (session-file session) (lambda () ((unbox notify-repaint)))))
  (define width (- full-width (bar-plan-left plan) (bar-plan-right plan) (if gut? 1 0)))
  (define height (+ 1 (- full-height (bar-plan-top plan) (bar-plan-bottom plan))))
  (define name (path->string (session-file session)))
  (define writing? (string=? (the-layer session) "write"))
  (define raw (session-text session))
  (define overlay
    (and
         (string-suffix? name ".aiu")
         (not (multi-raw? session)) (block-overlay session raw width height)))
  (define plain-text
    (cond
          [(or writing? (multi-raw? session)) raw]
          [else (page-view session raw width)]))
  (define pending (unbox pending-keys))
  (define menu (and (or (pair? pending) (member (the-layer session) (list "bar" "bar-level" "tab" "tab-level" "find" "pin"))) (menu-float (menu-text (the-layer session) pending (min width 66)) width)))
  (define text0 (if overlay (car overlay) plain-text))
  (define text (if (and gut? (not writing?) (not (multi-raw? session))) (gutter-apply session text0) text0))
  (define-values (row column) (point-line raw (the-point session)))
  (define plain-top
    (if (or writing? (multi-raw? session)) (viewport-top viewport row (max 1 (- height 1)))
        (add1 (the-view-top session))))
  (define top (max (if overlay (caddr overlay) plain-top) (let ([n (length (unbox title-rows))]) (if (> n 0) (+ n 2) 1))))
  (define text-shown
    (if menu (car (menu-screen menu top height)) text))
  (define where
    (if (string-suffix? name ".aiu")
        (let ([got (page-of (session-file session) (session-journal session))])
          (if (page? got)
              (let ([b (block-at got (the-point session))])
                (format "  ~a  ~a blocks" (if b (block-name b) "-") (length (page-blocks got))))
              ""))
        ""))
  (display
   (paint text-shown (if menu (cdr (menu-screen menu top height)) (if overlay (cadr overlay) (the-point session))) width height top
          (if (bar-plan-line? plan) (format "~a  ~a  ~a:~a~a" (file-name-from-path (session-file session))
                  (format "~a [~a]~a" (mode-label (the-layer session)) (unbox kind-filter) (if (unbox unsaved) "  unsaved: SPC s" "")) row column where) (bar-plan-text plan))
          writing?
          (or (and menu #t) (and overlay #t) (and (not writing?) (not (multi-raw? session)) (string-suffix? name ".aiu")))
          #:offset (bar-plan-top plan) #:left (bar-plan-left plan) #:full full-width #:overlay (string-append (bar-plan-overlay plan) (live-multi-overlay session raw top height (bar-plan-top plan) (bar-plan-left plan) width (and (not menu) (not overlay) (or writing? (not (string-suffix? name ".aiu")) (multi-raw? session)) #t)) (notify-overlay width height (+ 1 (bar-plan-top plan))))))
  (flush-output))

(define (viewport-top viewport row visible)
  (define shown (unbox viewport))
  (define next
    (cond
      [(< row shown) row]
      [(>= row (+ shown visible)) (max 1 (- row (sub1 visible)))]
      [else shown]))
  (set-box! viewport next)
  next)

(define (live-multi-overlay session raw top height offset left width shown?)
  (if (and shown? (multi-live? session))
      ((unbox multi-text-hook) raw top (max 1 (- height 1)) offset left width (the-layer session) (the-point session))
      ""))
