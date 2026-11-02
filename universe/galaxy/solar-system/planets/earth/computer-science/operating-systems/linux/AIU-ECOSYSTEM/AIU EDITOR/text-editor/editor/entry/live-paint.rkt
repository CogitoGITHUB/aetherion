#lang racket/base
;; One job: draw the live screen - the text, the bar, the menu, the cursors and the window of the view.

(require racket/list
         racket/path racket/port
         racket/path racket/port
         racket/string
         "../narration/print-console.rkt"
         "../commands/commands.rkt"
         "../join/hot-path.rkt"
         "../join/live-wire.rkt"
         "../join/protocol.rkt"
         "../drawing/screen.rkt"
         "../machine/terminal.rkt"
         "../routes/keyboard.rkt"
         "../routes/keymaps.rkt"
         "../routes/routes.rkt"
         "../notation/document.rkt"
         "../notation/host.rkt"
         "../notation/where.rkt"
         "../tui/blocks/blockview.rkt" "../tui/blocks/blocks-edit.rkt" "../tui/blocks/blocks-view.rkt"
         "../tui/blocks/blocks-move.rkt"
         "../tui/menu.rkt"
         "../tui/bar.rkt"
         "../tui/tabs/tabs.rkt"
         "../tui/tabs/finder.rkt"
         "../tui/notify.rkt"
         (only-in "../tui/box.rkt" paint-ready)
         "../tui/gutter.rkt"
         "../tui/gutterview.rkt"
         (only-in "../machine/directories.rkt" journal-path-for))

(provide repaint page-view pending-keys viewport-top live-multi-overlay)

;; page-view answers the text the view layer shows: an AIU NOTATION page
;; rendered, with its block markers gone, so the page reads as a page; any
;; other file is shown as its own text.
(define (page-view session raw width)
  (define name (path->string (session-file session)))
  (if (string-suffix? name ".aiu")
      (drawn-view session raw width)
      raw))

;; repaint draws the whole screen for the session as it stands: in the write
;; layer the text from the first visible line with the cursor on the point; in
;; every other layer the page as a reader sees it, with no cursor. The mode line
;; sits on the last row and names the file, the layer, the line and the block
;; the point is in — in the view too, so an arrow that moves the point says so
;; even though the page itself stays put. The window moves only when the point
;; would leave it.
;; paint-lock lets one paint run at a time, because the keys and the scan thread
;; both paint.
(define paint-lock (make-semaphore 1))

;; pending-keys holds the names of the keys typed so far while a sequence waits
;; for its next key, and nothing otherwise.
(define pending-keys (box (list)))

;; repaint draws the screen under the paint lock.
(define (repaint session viewport)
  (call-with-semaphore paint-lock (lambda () (repaint-now session viewport))))

;; repaint-now draws the whole screen for the session as it stands.
(define (repaint-now session viewport)
  (define-values (full-width full-height) (terminal-size))
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
  (define top (if overlay (caddr overlay) plain-top))
  ;; text-shown is the screen text. With a menu open it is a blank screen with the menu floating in the middle, so the page is hidden behind it.
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

;; viewport-top answers the first line shown at the top of the screen: the
;; window is left alone while the point is inside it, and it moves just enough
;; when the point leaves it. The answer is stored too, so the next key sees the
;; window this key left, and a moving point never drags the page under itself.
(define (viewport-top viewport row visible)
  (define shown (unbox viewport))
  (define next
    (cond
      [(< row shown) row]
      [(>= row (+ shown visible)) (max 1 (- row (sub1 visible)))]
      [else shown]))
  (set-box! viewport next)
  next)

;; live-multi-overlay answers the escape text that draws the extra cursors and the selections over the raw text,
;; or nothing when the screen does not show the raw text or no cursor or selection is in use.
(define (live-multi-overlay session raw top height offset left width shown?)
  (if (and shown? (multi-live? session))
      ((unbox multi-text-hook) raw top (max 1 (- height 1)) offset left width (the-layer session) (the-point session))
      ""))
