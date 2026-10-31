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
         "../dashboard/blockview.rkt"
         "../dashboard/bar.rkt"
         "../dashboard/tabs.rkt"
         "../dashboard/finder.rkt"
         "../dashboard/notify.rkt"
         (only-in "../dashboard/box.rkt" paint-ready)
         "../dashboard/gutter.rkt"
         "../dashboard/gutterview.rkt"
         (only-in "../machine/directories.rkt" journal-path-for))

;; live-session runs the live session on a file: the terminal goes raw, the keys
;; are read and run, and the terminal is given back when the session ends. A tab
;; key ends one round and names the next file, and the session goes on in the same
;; terminal with that file, so the hot path and the screen stay up while the tabs
;; change. The work not saved yet of every file stays in its own journal.
(define (live-session file journal)
  (unless (home-screen) (tab-show! (path->string file)))
  (raw-mode)
  (display "\u001b[?1049h")
  (dynamic-wind
    (lambda () #f)
    (lambda ()
      ;; The hot path is started once here, before the first frame, and kept
      ;; for the whole session: a key asks the child that is already running
      ;; instead of paying a program start for every letter.
      (unless (home-screen) (wire-start))
      (let next-round ([file file] [journal journal])
        (define session (make-session file journal))
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
        (set-box! home-repaint (lambda () (repaint session viewport)))
        (set-box! notify-repaint (lambda () (repaint session viewport)))
        (set-box! edit-hook (lambda () (gutter-stale!) (git-stale!)))
        (repaint session viewport)
        (set-box! paint-ready #t)
        (thread (lambda () (repaint session viewport)))
        (start-home-scan)
        (key-loop session (current-input-port) viewport)
        (define next (unbox tab-switch))
        (when next
          (set-box! tab-switch #f)
          (next-round (string->path next) (journal-path-for (string->path next))))))
    (lambda ()
      (set-box! home-repaint void)
      (wire-stop)
      (display "\u001b[?25h")
      (display "\u001b[?1049l")
      (restore-settings))))

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

;; kname answers the name of a key as shown: the space key is SPC.
(define (kname s) (if (string=? s "space") "SPC" s))

;; kseq answers a key or a sequence of keys as shown.
(define (kseq s) (string-join (map kname (sequence-of s)) " "))

;; cell-pad answers a string padded with spaces on the right to n characters.
(define (cell-pad s n)
  (string-append s (make-string (max 0 (- n (string-length s))) #\space)))

;; grid answers the lines of a titled table: a top edge with the title, a header
;; row, a line under it, one line for each row and a bottom edge, with a line
;; between every column.
(define (grid title headers rows)
  (define n (length headers))
  (define base
    (for/list ([i (in-range n)])
      (apply max (map (lambda (r) (string-length (list-ref r i))) (cons headers rows)))))
  (define head (string-append "╭─ " title " "))
  (define raw-total (+ (apply + (map (lambda (w) (+ w 2)) base)) n 1))
  (define extra (max 0 (- (+ (string-length head) 1) raw-total)))
  (define ws (append (take base (sub1 n)) (list (+ (last base) extra))))
  (define total (+ (apply + (map (lambda (w) (+ w 2)) ws)) n 1))
  (define (line l m r)
    (string-append l (string-join (map (lambda (w) (make-string (+ w 2) #\─)) ws) m) r))
  (define (row cells)
    (string-append "│"
                   (string-join (for/list ([c (in-list cells)] [w (in-list ws)])
                                  (string-append " " (cell-pad c w) " "))
                                "│")
                   "│"))
  (define top (string-append head (make-string (- total (string-length head) 1) #\─) "╮"))
  (append (list top (row headers) (line "├" "┼" "┤"))
          (map row rows)
          (list (line "╰" "┴" "╯"))))

;; enter-key answers the key of the visual layer that enters a layer: the key whose
;; command name ends with the layer name and -mode. A dash when there is none.
(define (enter-key l)
  (define hit
    (for/first ([b (in-list (keys-of "visual"))]
                #:when (string-suffix? (cadr b) (string-append l "-mode")))
      b))
  (if hit (kseq (car hit)) "-"))

;; menu-text answers the popup: table 1 holds the keys of the active layer that can
;; follow the pending keys, two key and command pairs to a row; table 2 holds every
;; mode with the key that enters it and its trigger. All of it is read from the key
;; tables, nothing is written by hand.
(define (menu-text layer pending width)
  (define following
    (for/list ([b (in-list (keys-of layer))]
               #:when (let ([s (sequence-of (car b))])
                        (and (> (length s) (length pending))
                             (equal? (take s (length pending)) pending))))
      (cons (string-join (map kname (drop (sequence-of (car b)) (length pending))) " ")
            (cadr b))))
  (define reachable
    (for/list ([l (in-list editor-layers)] #:when (not (string=? (enter-key l) "-"))) l))
  (define switch-to (filter (lambda (l) (not (string=? l layer))) reachable))
  (define mode-rows (menu-mode-rows switch-to width))
  (define shown
    (filter (lambda (p) (not (menu-mode-key? (cdr p) reachable))) following))
  (define key-width (apply max (cons 1 (map (lambda (p) (string-length (car p))) shown))))
  (define names (remove-duplicates (map (lambda (p) (menu-group-of (cdr p))) shown)))
  (define ordered (sort names < #:key menu-group-rank))
  (define group-boxes
    (append*
     (for/list ([g (in-list ordered)])
       (define cells
         (for/list ([p (in-list shown)] #:when (string=? (menu-group-of (cdr p)) g))
           (string-append (cell-pad (car p) key-width) "  " (menu-label-of (cdr p)))))
       (menu-box g (menu-cells cells (- width 8)) (- width 4)))))
  (define pick-cells
    (for/list ([b (in-list (keys-of "visual"))] #:when (and (regexp-match? #rx"^kind-" (cadr b)) (not (regexp-match? #rx" " (car b)))))
      (string-append (car b) "  " (menu-label-of (cadr b)))))
  (define pick-boxes
    (if (string=? layer "visual") (menu-box "pick · h t move between" (menu-cells pick-cells (- width 8)) (- width 4)) null))
  (define after     (if (null? pending) "keys" (format "keys after ~a" (string-join (map kname pending) " "))))
  (string-join
   (append (menu-table "modes · switch to" (car mode-rows) (cdr mode-rows) width)
           (menu-box (format "~a [~a] · ~a" (mode-label layer) (unbox kind-filter) after) (append pick-boxes group-boxes) width))
   "\n"))

;; menu-groups is the table of the menu: each command with the group box it sits in and the words it shows.
(define menu-groups
  (list (list "save" "file" "save") (list "quit" "file" "quit") (list "send" "file" "send")
        (list "check" "file" "check")
        (list "level-up" "page" "more rows")
        (list "next-block" "blocks" "next")
        (list "block-end" "blocks" "block end") (list "blocks" "blocks" "list")
        (list "focus-toggle" "view" "focus") (list "explorer" "view" "explorer") (list "home-open" "view" "dashboard")
        (list "block-up" "move" "block up") (list "block-down" "move" "block down")
        (list "move-left" "move" "left") (list "move-right" "move" "right")
        (list "move-up" "move" "up") (list "move-down" "move" "down")
        (list "block-move-up" "move" "move block up") (list "block-move-down" "move" "move block down")
        (list "block-edit" "edit" "edit raw") (list "block-text" "edit" "edit text")
        (list "delete" "edit" "backspace")
        (list "kind-any" "kind" "any block") (list "kind-paragraph" "kind" "paragraph")
        (list "kind-section" "kind" "section") (list "kind-code" "kind" "code")
        (list "kind-comment" "kind" "comment") (list "kind-title" "kind" "title")
        (list "kind-todo" "todo" "any todo") (list "kind-todo-open" "todo" "open todo")
        (list "kind-todo-done" "todo" "done todo")
        (list "tab-prev" "go" "tab before") (list "tab-next" "go" "tab after")
        (list "tab-open" "go" "open next page") (list "tab-close" "go" "close tab")
        (list "bar-place-next" "place" "next place") (list "bar-bottom" "place" "bottom")
        (list "bar-top" "place" "top") (list "bar-left" "place" "left")
        (list "bar-right" "place" "right") (list "bar-sides" "place" "sides")
        (list "tab-place-next" "place" "other place") (list "tab-top" "place" "top")
        (list "tab-bottom" "place" "bottom") (list "tab-join" "place" "share edge")
        (list "bar-style" "style" "docked or floating") (list "bar-hide" "style" "hide or show")
        (list "tab-hide" "style" "hide or show")
        (list "bar-less" "level" "hide one part") (list "bar-more" "level" "show one part")
        (list "tab-less" "level" "hide one level") (list "tab-more" "level" "show one level")
        (list "bar-level-mode" "level" "level adjuster") (list "tab-level-mode" "level" "level adjuster")
        (list "leave-write" "leave" "save and leave") (list "mode" "leave" "other layer")))

;; menu-group-order is the order of the group boxes; a group not named here comes last.
(define menu-group-order
  (list "file" "page" "blocks" "view" "move" "edit" "kind" "todo" "go" "place" "style" "level" "keys" "leave"))

;; menu-group-of answers the group box of a command; a command not in the table sits in keys.
(define (menu-group-of cmd)
  (let ([e (assoc cmd menu-groups)]) (if e (cadr e) "keys")))

;; menu-label-of answers the words shown for a command; a command not in the table shows its own name.
(define (menu-label-of cmd)
  (let ([e (assoc cmd menu-groups)]) (if e (caddr e) cmd)))

;; menu-group-rank answers the place of a group box in the order.
(define (menu-group-rank g)
  (let ([i (index-of menu-group-order g)]) (or i (length menu-group-order))))

;; menu-mode-key? asks whether a command enters one of the layers of the modes box, so its key shows there and not in the keys.
(define (menu-mode-key? cmd layers)
  (for/or ([l (in-list layers)]) (string-suffix? cmd (string-append l "-mode"))))

;; menu-box draws lines inside a box of the given total width, with the title on the top edge.
(define (menu-box title lines width)
  (define inner (- width 4))
  (define head (string-append "╭─ " title " "))
  (define top (string-append head (make-string (max 0 (- width (string-length head) 1)) #\─) "╮"))
  (append (list top)
          (for/list ([l (in-list lines)]) (string-append "│ " (cell-pad l inner) " │"))
          (list (string-append "╰" (make-string (- width 2) #\─) "╯"))))

;; menu-mode-rows answers the headers and the rows of the modes table: one row for each mode with its key, or two modes side by side when the screen is wide enough. The first half of the modes stands on the left.
(define (menu-mode-rows layers width)
  (define pairs (map (lambda (l) (list l (enter-key l))) layers))
  (define name-w (apply max (cons 4 (map (lambda (p) (string-length (car p))) pairs))))
  (define key-w (apply max (cons 3 (map (lambda (p) (string-length (cadr p))) pairs))))
  (define two? (and (> (length pairs) 1) (>= (- width 1) (* 2 (+ name-w key-w 6)))))
  (cond
    [two?
     (define rows-n (quotient (+ (length pairs) 1) 2))
     (define left (take pairs rows-n))
     (define right (drop pairs rows-n))
     (cons (list "mode" "key" "mode" "key")
           (for/list ([i (in-range rows-n)])
             (append (list-ref left i)
                     (if (< i (length right)) (list-ref right i) (list "" "")))))]
    [else (cons (list "mode" "key") pairs)]))

;; menu-table draws a table with a ruled line between every column and a header row, as wide as the given width. The spare width goes to the mode columns.
(define (menu-table title headers rows width)
  (define n (length headers))
  (define natural
    (for/list ([i (in-range n)])
      (apply max (map (lambda (r) (string-length (list-ref r i))) (cons headers rows)))))
  (define extra (max 0 (- width (+ (apply + natural) (* 3 n) 1))))
  (define name-cols (quotient (+ n 1) 2))
  (define ws
    (for/list ([w (in-list natural)] [i (in-naturals)])
      (if (even? i)
          (+ w (quotient extra name-cols) (if (< (quotient i 2) (remainder extra name-cols)) 1 0))
          w)))
  (define total (+ (apply + ws) (* 3 n) 1))
  (define (line l m r)
    (string-append l (string-join (map (lambda (w) (make-string (+ w 2) #\─)) ws) m) r))
  (define (row cells)
    (string-append "│"
                   (string-join (for/list ([c (in-list cells)] [w (in-list ws)])
                                  (string-append " " (cell-pad c w) " "))
                                "│")
                   "│"))
  (define head (string-append "╭─ " title " "))
  (define top (string-append head (make-string (max 0 (- total (string-length head) 1)) #\─) "╮"))
  (append (list top (row headers) (line "├" "┼" "┤"))
          (map row rows)
          (list (line "╰" "┴" "╯"))))

;; menu-float centers the lines of a menu in a screen of the given width by putting spaces in front of every line.
(define (menu-float text width)
  (define ls (string-split text "\n" #:trim? #f))
  (define widest (apply max (cons 0 (map string-length ls))))
  (define pad (make-string (max 0 (quotient (- width widest) 2)) #\space))
  (string-join (map (lambda (l) (string-append pad l)) ls) "\n"))

;; menu-screen answers the screen text and the point for an open menu: blank rows with the menu in the middle of the rows shown, and the point at the start of the menu so nothing scrolls.
(define (menu-screen menu top height)
  (define ms (string-split menu "\n" #:trim? #f))
  (define visible (max 1 (- height 1)))
  (define n (min (length ms) visible))
  (define before (quotient (- visible n) 2))
  (define lead (max 0 (sub1 top)))
  (define (blank k) (for/list ([i (in-range k)]) ""))
  (cons (string-join (append (blank lead) (blank before) (take ms n) (blank (- visible n before))) "\n")
        (+ lead before)))

;; menu-cells lays cells out in rows of equal columns that fit the inner width.
(define (menu-cells cells inner)
  (define cw (+ 2 (apply max (cons 1 (map string-length cells)))))
  (define per (max 1 (quotient (+ inner 2) cw)))
  (let loop ([cs cells])
    (cond
      [(null? cs) null]
      [else
       (define n (min per (length cs)))
       (cons (string-trim (string-join (for/list ([c (in-list (take cs n))]) (cell-pad c cw)) "") #:left? #f)
             (loop (drop cs n)))])))

;; repaint draws the screen under the paint lock.
(define (repaint session viewport)
  (call-with-semaphore paint-lock (lambda () (repaint-now session viewport))))

;; repaint-now draws the whole screen for the session as it stands.
(define (repaint-now session viewport)
  (define-values (full-width full-height) (terminal-size))
  (define plan
    (bar-plan-of session (unbox pending-keys) full-width full-height (and (home-screen) #t)
                 (lambda () ((unbox home-repaint)))))
  (define gut? (and (not (home-screen)) (string-suffix? (path->string (session-file session)) ".aiu")))
  (when gut? (gutter-refresh-maybe (session-file session) (lambda () ((unbox notify-repaint)))))
  (define width (- full-width (bar-plan-left plan) (bar-plan-right plan) (if gut? 1 0)))
  (define height (+ 1 (- full-height (bar-plan-top plan) (bar-plan-bottom plan))))
  (define name (path->string (session-file session)))
  (define writing? (string=? (the-layer session) "write"))
  (define raw (session-text session))
  (define overlay
    (and (not (home-screen))
         (string-suffix? name ".aiu")
         (block-overlay session raw width height)))
  (define home (home-screen))
  (define plain-text
    (cond [home (string-join (home (the-level session) (unbox home-explorer)) "\n")]
          [writing? raw]
          [else (page-view session raw width)]))
  (define pending (unbox pending-keys))
  (define menu (and (not home) (or (pair? pending) (member (the-layer session) (list "bar" "bar-level" "tab" "tab-level" "find"))) (menu-float (menu-text (the-layer session) pending (min width 66)) width)))
  (define text0 (if overlay (car overlay) plain-text))
  (define text (if (and gut? (not writing?)) (gutter-apply session text0) text0))
  (define-values (row column) (point-line raw (the-point session)))
  (define plain-top
    (if writing? (viewport-top viewport row (max 1 (- height 1)))
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
                  (format "~a [~a]" (mode-label (the-layer session)) (unbox kind-filter)) row column where) (bar-plan-text plan))
          writing?
          (or (and home #t) (and menu #t) (and overlay #t) (and (not writing?) (string-suffix? name ".aiu")))
          #:offset (bar-plan-top plan) #:left (bar-plan-left plan) #:full full-width #:overlay (string-append (bar-plan-overlay plan) (notify-overlay width height (+ 1 (bar-plan-top plan))))))
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

;; outcome is what one round of the loop did: the bytes that are left
;; for the next round, and whether the session goes on. The bytes are
;; the word "wait" when the keys so far are the start of a sequence and
;; the next key must arrive.
(struct outcome (rest go-on?) #:transparent)

;; read-available answers the bytes that have already arrived, or the word
;; "eof" at the end of the input. It waits for the FIRST byte — that wait is
;; the wait for a key, and no clock decides it — and then takes whatever else
;; is already there. That matters for a key a terminal sends as several bytes
;; in one write: an arrow is escape, "[", "D" in one write, and read one byte
;; at a time it would be decoded as the escape key and two letters.
(define (read-available port chunk)
  (define n (read-bytes-avail! chunk port))
  (cond
    [(eof-object? n) 'eof]
    [(zero? n) '()]
    [else (for/list ([i (in-range n)]) (bytes-ref chunk i))]))

;; key-loop reads the bytes that arrive and runs what they mean. The bytes
;; that have arrived so far are kept: the hot path is asked about all of them,
;; so a key that is the start of a sequence is seen whole. Everything that is
;; already in the buffer is walked before the read waits again, so a paste is
;; typed in the order it was pasted.
(define (key-loop session port viewport)
  (define chunk (make-bytes 1024))
  (let loop ([buffer '()])
    (define arrived (read-available port chunk))
    (unless (eq? arrived 'eof)
      (let walk ([pending (append buffer arrived)])
        (cond
          [(null? pending) (loop '())]
          [else
           (define result (act-on session pending))
             (set-box! pending-keys (if (eq? (outcome-rest result) (quote wait)) (map car (key-runs pending)) (list)))
           (repaint session viewport)
           (cond
             [(eq? (outcome-rest result) 'wait)
              (loop pending)]
             [(outcome-go-on? result)
              (walk (outcome-rest result))]
             [else (void)])])))))

;; longest-binding answers how many leading keys of the buffer form a binding:
;; the longest run of them the layer binds. Zero when the layer binds none of
;; the leading runs.
(define (longest-binding layer names)
  (let loop ([k (length names)])
    (cond
      [(zero? k) 0]
      [(binding-of layer (string-join (take names k) " ")) k]
      [else (loop (sub1 k))])))

;; act-on runs what the bytes mean and answers what the round did: the
;; bytes that are left for the next round, and whether the session goes
;; on.
;;
;; The runs are walked from the FRONT, one key at a time. A terminal may hand
;; the editor a whole paste at once, and a chunk is not a command: "tab s tab
;; q" must save and quit, and "one two" must be typed as written. So the
;; longest leading run that is a binding runs first; a run that is the start
;; of a sequence waits for the next key; and otherwise the FIRST key alone is
;; acted on, with the rest of the bytes kept for the next round.
(define (act-on session buffer)
  (define runs (key-runs buffer))
  (define digit (and (home-screen) (pair? runs) (text-of (car (car runs)))))
  (define picked
    (and digit
         (regexp-match? #px"^[1-9]$" digit)
         ((home-pick) (string->number digit))))
  (if picked
      (begin (set-box! home-chosen picked)
             (outcome (list) #f))
      (act-on-file session buffer)))

;; act-on-file runs the keys of a session that has a file.
(define (act-on-file session buffer)
  (define runs (key-runs buffer))
  (cond
    [(null? runs)
     ;; The bytes hold no whole key yet: the next byte is read, and the
     ;; read waits for it. No clock decides this.
     (outcome 'wait #t)]
    [else
     (define names (map car runs))
     (define layer (the-layer session))
     (define matched (longest-binding layer names))
     (cond
       [(> matched 0)
        ;; The longest leading sequence is a command: run it, and keep the
        ;; bytes that came after it.
        (outcome (drop-bytes buffer (take runs matched))
                 (run-it session (binding-of layer (string-join (take names matched) " "))))]
       [(prefix-of? layer names)
        ;; The keys so far are the start of a sequence: the next key is
        ;; waited for, and the wait is an action.
        (outcome 'wait #t)]
       [(and (not (string=? layer "write")) (text-of (car names)))
        ;; A key that carries text writes NOTHING in a reading layer. The
        ;; write layer is entered by its own key — w in the visual
        ;; layer — and by nothing else, so a stray letter can never start
        ;; writing and the page a reader is reading cannot change under the
        ;; key. The key is taken and nothing is said: the mode line already
        ;; names the layer, and a message over the page would break the frame.
        (notify! "warn" (format "no key: ~a in ~a" (string-join names " ") (mode-label layer)))
        (outcome (drop-bytes buffer (list (car runs))) #t)]
       [(text-of (car names))
        ;; In the write layer a key that carries text IS the text: a space is
        ;; a space, a return is the newline.
        (outcome (drop-bytes buffer (list (car runs)))
                 (run-it-words session "type" (list (text-of (car names)))))]
       [else
        ;; The first key means nothing to anybody: it is said out loud
        ;; and the rest of the bytes are kept.
        (notify! "warn" (format "no key: ~a in ~a" (string-join names " ") (mode-label layer)))
        (outcome (drop-bytes buffer (list (car runs))) #t)])]))

;; run-it runs one command and answers whether the session goes on. Nothing is
;; printed: the screen is the answer. The text is drawn where it stands, the
;; mode line says the layer and the line, and a line of "point=12" or
;; "bytes=5" over the page would only be painted over by the next frame — or,
;; worse, break the frame it landed in. The commands still answer; the live
;; session chooses not to say the answer out loud.
(define (run-it session line)
  (if (home-screen)
      (home-run session line)
      (block-guard session line (lambda () (run-it-file session line)))))

;; run-it-file runs one command on a session that has a file.
(define (run-it-file session line)
  (car (run-command session line)))

;; run-it-words runs one command whose words are already split, and answers
;; whether the session goes on. A key's text is one word even when that word is
;; a space, so the live session hands the words over whole. It is silent for
;; the same reason run-it is: the paint is the answer.
(define (run-it-words session name words)
  (if (home-screen) #t (run-it-words-file session name words)))

;; run-it-words-file runs one command, its words already split, on a session that has a file.
(define (run-it-words-file session name words)
  (car (run-command-words session name words)))

;; drop-bytes answers the bytes that are left when the keys that were
;; run are taken out of the buffer. The bytes are dropped from the FRONT,
;; because the keys that were run are the first ones in the buffer.
(define (drop-bytes buffer runs)
  (define taken (for/sum ([run (in-list runs)]) (cdr run)))
  (if (>= taken (length buffer))
      '()
      (drop buffer taken)))

;; home-screen, when set, is a function from the level to the lines of the
;; dashboard: the session paints those lines instead of a file.
(define home-screen (make-parameter #f))

;; The home screen keeps four things: the panel flag, the page the person
;; chose, the function that answers the nth page, and the function that scans
;; again.
(define home-explorer (box #f))
;; home-chosen holds the page the person picked on the home screen.
(define home-chosen (box #f))
;; home-pick answers the path of the nth page of the home screen.
(define home-pick (make-parameter (lambda (n) #f)))
;; home-refresh scans the home screen again.
(define home-refresh (make-parameter void))

;; home-repaint holds the function that paints the open home session, and void
;; when none is open, so a scan that lands late paints nothing.
(define home-repaint (box void))

;; home-repaint-later paints the home session, if one is still open.
(define (home-repaint-later)
  ((unbox home-repaint)))

;; start-home-scan starts the scan of the home screen in a thread. It runs
;; after the first paint, so the screen is there before the scan begins.
(define (start-home-scan)
  (when (home-screen)
    ((home-refresh) home-repaint-later)))

;; home-run runs one command on the home screen. Only the commands that need
;; no file run: the level keys, quit and the visual layer. The panel and the
;; scan are answered here. Everything else is taken and nothing is done, so a
;; command that needs a file cannot fail on a screen that has none.
(define (home-run session line)
  (define words (string-split line))
  (define name (if (null? words) "" (car words)))
  (cond
    [(member name (list "level-up" "quit" "visual-mode"))
     (car (run-command session line))]
    [(string=? name "explorer")
     (set-box! home-explorer (not (unbox home-explorer)))
     #t]
    [else #t]))

;; The live session, for the entry above it.
(provide live-session home-screen home-pick home-refresh home-chosen home-explorer)
