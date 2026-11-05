#lang racket/base

(require racket/list
         racket/path racket/port
         racket/path racket/port
         racket/string
         "../../narration/print-console-shared.rkt"
         "../../commands/commands-shared.rkt"
         "../../join/hot-path-shared.rkt"
         "../../join/live-wire-shared.rkt"
         "../../join/protocol-shared.rkt"
         "../../drawing/screen.rkt"
         "../../machine/terminal.rkt"
         "../../routes/keyboard.rkt"
         "../../routes/keymaps-shared.rkt"
         "../../routes/routes.rkt"
         "../../bridge/document-shared.rkt"
         "../../bridge/host-shared.rkt"
         "../../bridge/where-shared.rkt"
         "../../tui/blocks/blockview.rkt" "../../tui/blocks/blocks-edit.rkt" "../../tui/blocks/blocks-view.rkt"
         "../../tui/blocks/blocks-move.rkt"
         "../../tui/bar/bar-menu-shared.rkt"
         "../../tui/bar/bar.rkt"
         "../../tui/tabs/tabs-shared.rkt"
         "../../tui/tabs/finder.rkt"
         "../../tui/notify/notify.rkt"
         (only-in "../../tui/float/box-shared.rkt" paint-ready)
         "../../tui/gutter/gutter.rkt"
         "../../tui/gutter/gutterview.rkt"
         (only-in "../../machine/directories-shared.rkt" journal-path-for))

(require (only-in "../../tui/bar/bar-state-shared.rkt" title-rows split-panes-on) "../../tui/split/split-state.rkt" "../../tui/split/split-layout.rkt" "../../tui/split/split-overlay.rkt" "../../tui/split/split-view.rkt" (only-in "../../tui/float/pins.rkt" pins-now first-start cur-start)) (require (only-in "../../tui/float/box-shared.rkt" edge-line rule-line body-line draw-at) (only-in "../../tui/float/float-state-shared.rkt" float-visible float-active float-share float-rect float-names float-tabs-text float-current-file))

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
  (define panes? (pair? (cdr (split-layout-ids (unbox split-tree)))))
  (set-box! split-panes-on panes?)
  (set-box! title-rows (if panes? (list) (title-box-of session full-width)))
  (define plan
    (bar-plan-of session (unbox pending-keys) full-width full-height
                 void))
  (define gut? (and (string-suffix? (path->string (session-file session)) ".aiu")))
  (when (and gut? (not (unbox unsaved))) (gutter-refresh-maybe (session-file session) (lambda () ((unbox notify-repaint)))))
  (define region-width (- full-width (bar-plan-left plan) (bar-plan-right plan)))
  (define region-rows (- full-height (bar-plan-top plan) (bar-plan-bottom plan)))
  (define rects (split-layout-rects (unbox split-tree) 0 0 region-width region-rows))
  (define focus-rect (or (assoc (unbox split-focus) rects) (list 1 0 0 region-width region-rows)))
  (define width (if panes? (- (cadddr focus-rect) 2 (if gut? 1 0)) (- region-width (if gut? 1 0))))
  (define height (if panes? (- region-rows (caddr focus-rect)) (+ 1 region-rows)))
  (define render-height (if panes? (- (list-ref focus-rect 4) 1) height))
  (define pane-offset-extra (if panes? (+ (caddr focus-rect) 1) 0))
  (define pane-left-extra (if panes? (+ (cadr focus-rect) 1) 0))
  (define name (path->string (session-file session)))
  (define writing? (string=? (the-layer session) "write"))
  (define raw (session-text session))
  (define overlay
    (and
         (string-suffix? name ".aiu")
         (not (multi-raw? session)) (block-overlay session raw width render-height)))
  (define plain-text
    (cond
          [(or writing? (multi-raw? session)) raw]
          [else (page-view session raw width)]))
  (define pending (unbox pending-keys))
  (define menu (and #f (or (pair? pending) (member (the-layer session) (list "bar" "bar-level" "tab" "tab-level" "find" "pin"))) (menu-float (menu-text (the-layer session) pending (min width 66)) width)))
  (define text0 (if overlay (car overlay) plain-text))
  (define text (if (and gut? (not writing?) (not (multi-raw? session))) (gutter-apply session text0) text0))
  (define-values (row column) (point-line raw (the-point session)))
  (define plain-top
    (if (or writing? (multi-raw? session)) (viewport-top viewport row (max 1 (- render-height 1)))
        (add1 (the-view-top session))))
  (define top (max (if overlay (caddr overlay) plain-top) (let ([n (length (unbox title-rows))]) (if (> n 0) (+ n 2) 1))))
  (define pane-overlay
    (if panes?
        (split-overlay-draw rects (unbox split-focus)
          (lambda (id focused? inner-width inner-height)
            (define here (path->string (path->complete-path (session-file session))))
            (define file (if focused? here (or (split-state-file-of id) here)))
            (cons (let ([n (file-name-from-path file)]) (if n (path->string n) file))
                  (if focused? (list) (split-view-lines file inner-width inner-height))))
          (bar-plan-top plan) (bar-plan-left plan))
        ""))
  (define float-overlay-text
    (if (unbox float-visible)
        (let-values ([(fx fy fw fh) (float-rect (unbox float-share) region-width region-rows)])
          (let* ([file (path->string (path->complete-path (float-current-file)))]
                 [lines (split-view-lines file (max 1 (- fw 4)) (max 0 (- fh 2)))])
            (draw-at (append (list (edge-line "╭" "╮" (list-ref float-names (unbox float-active)) (float-tabs-text (unbox float-active)) fw))
                             (for/list ([i (in-range (max 0 (- fh 2)))])
                               (body-line (if (< i (length lines)) (list-ref lines i) "") fw))
                             (list (rule-line "╰" "╯" fw)))
                     (+ (bar-plan-top plan) fy 1) (+ (bar-plan-left plan) fx 1))))
        ""))
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
          #:offset (+ (bar-plan-top plan) pane-offset-extra) #:left (+ (bar-plan-left plan) pane-left-extra) #:full full-width #:overlay (string-append (bar-plan-overlay plan) pane-overlay float-overlay-text (live-multi-overlay session raw top (if panes? render-height height) (+ (bar-plan-top plan) pane-offset-extra) (+ (bar-plan-left plan) pane-left-extra) width (and (not menu) (not overlay) (or writing? (not (string-suffix? name ".aiu")) (multi-raw? session)) #t)) (notify-overlay width height (+ 1 (bar-plan-top plan))))))
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
