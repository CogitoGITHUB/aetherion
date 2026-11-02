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
         "../tui/blockview.rkt" "../tui/blocks-edit.rkt" "../tui/blocks-view.rkt"
         "../tui/blocks-move.rkt"
         "../tui/menu.rkt"
         "../tui/bar.rkt"
         "../tui/tabs.rkt"
         "../tui/finder.rkt"
         "../tui/notify.rkt"
         (only-in "../tui/box.rkt" paint-ready)
         "../tui/gutter.rkt"
         "../tui/gutterview.rkt"
         (only-in "../machine/directories.rkt" journal-path-for))

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
           (define trace-t0 (current-inexact-milliseconds))
           (define result (act-on session pending))
           (trace-key! pending trace-t0 result session)
             (set-box! pending-keys (if (eq? (outcome-rest result) (quote wait)) (map car (key-runs pending)) (list)))
           (repaint session viewport)
           (cond
             [(eq? (outcome-rest result) 'wait)
              (loop pending)]
             [(outcome-go-on? result)
              (walk (outcome-rest result))]
             [else (void)])])))))

;; trace-session! appends one line to the trace log when AIU_TRACE is set: the file a session opens in one line.
(define (trace-session! file)
  (when (getenv "AIU_TRACE")
    (with-handlers ([void void])
      (call-with-output-file (build-path (find-system-path (quote home-dir)) ".aiu-trace.log") #:exists (quote append)
        (lambda (o) (fprintf o "~a session file ~a\n" (current-inexact-milliseconds) file))))))

;; trace-key! appends one line to the trace log when AIU_TRACE is set, and does nothing otherwise.
(define (trace-key! pending t0 result session)
  (when (getenv "AIU_TRACE")
    (with-handlers ([void void])
      (call-with-output-file (build-path (find-system-path (quote home-dir)) ".aiu-trace.log") #:exists (quote append)
        (lambda (o)
          (fprintf o "~a act-on ~a ms pending ~s go-on ~a layer ~a rest ~a\n" (current-inexact-milliseconds) (- (current-inexact-milliseconds) t0) (if (> (length pending) 3) (take pending 3) pending) (outcome-go-on? result) (the-layer session) (let ([r (outcome-rest result)]) (if (list? r) (length r) r))))))))

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
  (act-on-file session buffer))

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
  (block-guard session line (lambda () (run-it-file session line))))

;; run-it-file runs one command on a session that has a file.
(define (run-it-file session line)
  (car (run-command session line)))

;; run-it-words runs one command whose words are already split, and answers
;; whether the session goes on. A key's text is one word even when that word is
;; a space, so the live session hands the words over whole. It is silent for
;; the same reason run-it is: the paint is the answer.
(define (run-it-words session name words)
  (run-it-words-file session name words))

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

(provide live-session)

;; live-multi-overlay answers the escape text that draws the extra cursors and the selections over the raw text,
;; or nothing when the screen does not show the raw text or no cursor or selection is in use.
(define (live-multi-overlay session raw top height offset left width shown?)
  (if (and shown? (multi-live? session))
      ((unbox multi-text-hook) raw top (max 1 (- height 1)) offset left width (the-layer session) (the-point session))
      ""))
