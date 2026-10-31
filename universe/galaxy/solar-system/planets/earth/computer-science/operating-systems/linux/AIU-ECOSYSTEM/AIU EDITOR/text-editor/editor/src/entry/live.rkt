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
         racket/path
         racket/port
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
        (repaint session viewport)
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
  (define pair-rows
    (let loop ([ps following])
      (cond
        [(null? ps) null]
        [(null? (cdr ps)) (list (list (car (car ps)) (cdr (car ps)) "" ""))]
        [else (cons (list (car (car ps)) (cdr (car ps)) (car (cadr ps)) (cdr (cadr ps)))
                    (loop (cddr ps)))])))
  (define mode-rows
    (for/list ([l (in-list editor-layers)])
      (define t (assoc l trigger-of))
      (list (string-append (if (string=? l layer) "> " "  ") l)
            (enter-key l)
            (if t (kname (cdr t)) "-"))))
  (string-join
   (append (grid (if (null? pending) (format "~a · keys" layer) (format "~a · keys after ~a" layer (string-join (map kname pending) " ")))
                 (list "key" "command" "key" "command")
                 pair-rows)
           (grid "modes" (list "mode" "enter" "trigger") mode-rows))
   "\n"))

;; repaint draws the screen under the paint lock.
(define (repaint session viewport)
  (call-with-semaphore paint-lock (lambda () (repaint-now session viewport))))

;; repaint-now draws the whole screen for the session as it stands.
(define (repaint-now session viewport)
  (define-values (full-width full-height) (terminal-size))
  (define plan
    (bar-plan-of session (unbox pending-keys) full-width full-height (and (home-screen) #t)
                 (lambda () ((unbox home-repaint)))))
  (define width (- full-width (bar-plan-left plan) (bar-plan-right plan)))
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
  (define menu (and (not home) (or (pair? pending) (member (the-layer session) (list "bar" "bar-level" "tab" "tab-level" "find"))) (menu-text (the-layer session) pending width)))
  (define text (if overlay (car overlay) plain-text))
  (define-values (row column) (point-line raw (the-point session)))
  (define plain-top
    (if writing? (viewport-top viewport row (max 1 (- height 1)))
        (add1 (the-view-top session))))
  (define top (if overlay (caddr overlay) plain-top))
  ;; text-shown is the page with the menu drawn over its bottom rows, so the
  ;; page the person is on stays on the screen above it.
  (define text-shown
    (if menu
        (let* ([ls (string-split text "\n" #:trim? #f)]
               [ms (string-split menu "\n" #:trim? #f)]
               [visible (max 1 (- height 1))]
               [n (min (length ms) visible)]
               [start (max 0 (+ (sub1 top) (- visible n)))]
               [padded (if (< (length ls) start)
                           (append ls (for/list ([i (in-range (- start (length ls)))]) ""))
                           ls)])
          (string-join (append (take padded start)
                               (take ms n)
                               (if (> (length padded) (+ start n)) (drop padded (+ start n)) (list)))
                       "\n"))
        text))
  (define where
    (if (string-suffix? name ".aiu")
        (let ([got (page-of (session-file session) (session-journal session))])
          (if (page? got)
              (let ([b (block-at got (the-point session))])
                (format "  ~a  ~a blocks" (if b (block-name b) "-") (length (page-blocks got))))
              ""))
        ""))
  (display
   (paint text-shown (if overlay (cadr overlay) (the-point session)) width height top
          (if (bar-plan-line? plan) (format "~a  ~a  ~a:~a~a" (file-name-from-path (session-file session))
                  (the-layer session) row column where) (bar-plan-text plan))
          writing?
          (or (and home #t) (and menu #t) (and overlay #t) (and (not writing?) (string-suffix? name ".aiu")))
          #:offset (bar-plan-top plan) #:left (bar-plan-left plan) #:full full-width #:overlay (bar-plan-overlay plan)))
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
        (outcome (drop-bytes buffer (list (car runs))) #t)]
       [(text-of (car names))
        ;; In the write layer a key that carries text IS the text: a space is
        ;; a space, a return is the newline.
        (outcome (drop-bytes buffer (list (car runs)))
                 (run-it-words session "type" (list (text-of (car names)))))]
       [else
        ;; The first key means nothing to anybody: it is said out loud
        ;; and the rest of the bytes are kept.
        (print-line (format "no key is bound to ~a" (car names)))
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
    [(member name (list "level-down" "level-up" "quit" "visual-mode"))
     (car (run-command session line))]
    [(string=? name "explorer")
     (set-box! home-explorer (not (unbox home-explorer)))
     #t]
    [(string=? name "view")
     ((home-refresh))
     #t]
    [else #t]))

;; The live session, for the entry above it.
(provide live-session home-screen home-pick home-refresh home-chosen home-explorer)
