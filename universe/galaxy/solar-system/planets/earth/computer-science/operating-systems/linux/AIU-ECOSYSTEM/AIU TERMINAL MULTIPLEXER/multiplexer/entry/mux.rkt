#lang racket/base
(require (only-in racket/port open-output-nowhere) racket/system racket/list racket/file racket/string
         "../pane/pane-pty.rkt" "../pane/pane-grid.rkt" "../pane/pane-text-decode.rkt" "../pane/pane-unit.rkt"
         "../pane/pane-keys.rkt" "../pane/pane-scroll-keys.rkt" "../pane/pane-buffer-keys.rkt" "../pane/pane-split-keys.rkt"
         "../tui/layout/layout-tree-shared.rkt" "../tui/layout/layout-buffers-shared.rkt" "../tui/float/float-state-shared.rkt"
         "../frame/frame-bars.rkt" "../frame/frame-paint.rkt" "../frame/frame-diff.rkt" "../frame/frame-compose.rkt"
         "../machine/terminal.rkt"
         (only-in "../tui/bar/bar-clock-shared.rkt" clock-stamp))

(define session-name "shell")
(define stty-program "/usr/bin/stty")
(define bar-refresh-milliseconds 1000)
(define quit-ask (box #f))
(define (pulse-sgr2 red?)
  (if red?
      (pulse-sgr)
      (let* ([p (modulo (quotient (inexact->exact (floor (current-inexact-milliseconds))) 50) 40)]
             [up (if (< p 20) p (- 40 p))]
             [v (+ 110 (quotient (* up 145) 20))])
        (format "\u001b[38;2;~a;~a;~am" v v v))))
(define (pulse-rect! cells columns rows bar-count x y w h red?)
  (define sgr (pulse-sgr2 red?))
  (for* ([r (in-range (+ bar-count y) (min rows (+ bar-count y h)))]
         [c (in-range x (min columns (+ x w)))])
    (define row (vector-ref cells r))
    (define cell (vector-ref row c))
    (when (and (string=? (cdr cell) "")
               (not (memv (car cell) (list #\space #\nul))))
      (vector-set! row c (cons (car cell) sgr)))))
(define pulse-last (box -1))
(define (pulse-phase)
  (modulo (quotient (inexact->exact (floor (current-inexact-milliseconds))) 50) 60))
(define (pulse-sgr)
  (define phase (pulse-phase))
  (define seg (quotient phase 20))
  (define t (/ (modulo phase 20) 20.0))
  (define stops (vector (vector 110 110 110) (vector 255 255 255) (vector 220 40 40)))
  (define from (vector-ref stops seg))
  (define to (vector-ref stops (modulo (+ seg 1) 3)))
  (define (mix i)
    (inexact->exact (floor (+ (vector-ref from i) (* t (- (vector-ref to i) (vector-ref from i)))))))
  (format "\u001b[38;2;~a;~a;~am" (mix 0) (mix 1) (mix 2)))
(define (pulse-cells! cells columns rows)
  (define sgr (pulse-sgr))
  (for* ([r (in-range rows)] [c (in-range columns)])
    (define row (vector-ref cells r))
    (define cell (vector-ref row c))
    (when (and (string=? (cdr cell) "") (not (memv (car cell) (list #\space #\nul))))
      (vector-set! row c (cons (car cell) sgr)))))
(define (quit-box-lines)
  (define w 34)
  (define (row text)
    (string-append "│ " text
                   (make-string (max 0 (- w 4 (string-length text))) #\space)
                   " │"))
  (list (string-append "╭─┤ quit ├" (make-string (- w 11) #\─) "╮")
        (row "Quit the multiplexer?")
        (row "enter or space  quit")
        (row "n  stay")
        (string-append "╰" (make-string (- w 2) #\─) "╯")))
(define (draw-quit-box! cells columns rows)
  (define lines (quit-box-lines))
  (define top (max 0 (quotient (- rows (length lines)) 2)))
  (define left (max 0 (quotient (- columns 34) 2)))
  (for ([l (in-list lines)] [i (in-naturals)])
    (overlay-text! cells columns rows (+ top i) left l)))
(define size-check-milliseconds 400)

(define status-home (or (getenv "HOME") ""))
(define server-state (box "checking"))
(define (status-thread-start!)
  (thread
   (lambda ()
     (let loop ()
       (define bin (build-path status-home ".local/share/aiu-pm/prefix/ecosystem-server/current/bin/ecosystem-server"))
       (set-box! server-state
                 (cond [(not (file-exists? bin)) "not installed"]
                       [(with-handlers ([void (lambda (why) #f)])
                          (parameterize ([current-output-port (open-output-nowhere)] [current-error-port (open-output-nowhere)])
                            (= 0 (system*/exit-code bin "ping")))) "running"]
                       [else "stopped"]))
       (sleep 2)
       (loop)))))
(define (dev-on?) (file-exists? (build-path status-home ".local/state/aiu-ecosystem/dev-mode")))
(define (error-count)
  (define d (build-path status-home ".local/state/aiu-ecosystem/dev-errors"))
  (if (directory-exists? d) (length (directory-list d)) 0))
(define (strip-blank rows)
  (define (blank? r) (string=? "" (string-trim (regexp-replace* #rx"\e\\[[0-9;]*[A-Za-z]" r ""))))
  (let loop ([l rows]) (if (and (pair? l) (blank? (car l))) (loop (cdr l)) l)))
(define (box3 text)
  (define n (+ 2 (string-length text)))
  (list (string-append "╭" (make-string n #\─) "╮") (string-append "│ " text " │") (string-append "╰" (make-string n #\─) "╯")))
(define (decorate-bars rows) (strip-blank rows))

(define (dev-text)
  (define n (error-count))
  (cond [(dev-on?)
         (if (> n 0) (format "DEV MODE errors ~a" n) "DEV MODE")]
        [(> n 0) (format "BUILD ERRORS ~a" n)]
        [else ""]))
(define (top-label layer) layer)
(define (bottom-label columns)
  (define n (error-count))
  (define r
    (string-append "aiu server " (if (equal? (unbox server-state) "running") "●" "○")
                   "  aiu dev " (if (dev-on?) "●" "○")
                   (if (> n 0) (format " errors ~a" n) "")))
  (string-append (clock-stamp (max 0 (- columns (string-length r) 25)) #t #t)
                 "\u0001" r))

(define (tabs-for unit default)
  (define g (and unit (pane-unit-grid unit)))
  (define t (and g (pane-grid-alternate g) (hash-ref pane-grid-tabs g #f)))
  (if (and t (not (string=? t ""))) t default))

(define (sync-app-layer! kb unit)
  (when unit
    (define l (key-state-layer (unbox kb)))
    (when (member l (list "editor" "shell"))
      (define want (if (hash-ref pane-grid-tabs (pane-unit-grid unit) #f) "editor" "shell"))
      (unless (string=? l want)
        (set-box! kb (key-state want (key-state-pending (unbox kb)) (key-state-pinned (unbox kb))))))))

(define (run-multiplexer)
  (define-values (first-columns first-height) (terminal-size))
  (define bars (bars-link-open))
  (void (status-thread-start!))
  (define key-state-box (box (initial-key-state)))
  (define screen-columns (box first-columns))
  (define screen-height (box first-height))
  (define buffers-state (box (layout-buffers-new "main" 1)))
  (define pane-counter (box 1))
  (define buffer-counter (box 1))
  (define panes (make-hash))
  (define dead-panes (box (list)))
  (define bar-cache (make-hash))
  (define shell-cwd (box ""))
  (define lock (make-semaphore 1))
  (define state-lock (make-semaphore 1))
  (define finished (make-semaphore 0))
  (define dirty (box #t))
  (define float-shown (box #f))
  (define float-index (box 0))
  (define float-preset (box 100))
  (define ecosystem-root
    (let ([raw (environment-variables-ref (current-environment-variables) #"AIU_ROOT")])
      (if raw (bytes->path raw) (current-directory))))
  (define (float-active-id) (float-pane-id-of (unbox float-index)))
  (define (float-rect-now)
    (float-rect (unbox float-preset) (unbox screen-columns) (max 5 (- (unbox screen-height) (length (unbox bar-rows))))))
  (define (show-float! index)
    (set-box! float-index index)
    (set-box! float-shown #t))
  (define (tile-count) (length (filter (lambda (id) (>= id 0)) (hash-keys panes))))
  (define (open-float-pane! id columns rows)
    (void)
    (define unit (if (= id (float-pane-id-of 3)) (pane-unit-open-program id columns rows (string-append (or (getenv "HOME") "") "/.local/share/aiu-pm/prefix/aiu-splash/live/bin/aiu-splash") (list "watch")) (pane-unit-open id columns rows (unbox shell-cwd))))
    (hash-set! panes id unit)
    (start-output-thread! unit))
  (define (fit-float!)
    (when (unbox float-shown)
      (define-values (x y width height) (float-rect-now))
      (define id (float-active-id))
      (define columns (- width 2))
      (define rows (- height 2))
      (define unit (hash-ref panes id #f))
      (cond
        [(not unit) (open-float-pane! id columns rows)]
        [else
         (define grid (pane-unit-grid unit))
         (unless (and (= columns (pane-grid-columns grid)) (= rows (pane-grid-height grid)))
           (call-with-semaphore lock (lambda () (pane-grid-resize! grid columns rows)))
           (pane-set-size! (pane-unit-link unit) columns rows))])))
  (define (float-entries)
    (define unit (and (unbox float-shown) (hash-ref panes (float-active-id) #f)))
    (if unit
        (let-values ([(x y width height) (float-rect-now)])
          (list (list x y width height (pane-unit-grid unit) (unbox (pane-unit-scroll unit)) #t
                      (list-ref float-names (unbox float-index)) (float-tabs-text (unbox float-index)))))
        (list)))

  (define (current-layout)
    (define state (unbox buffers-state))
    (layout-buffer-layout (list-ref (layout-buffer-list-buffers state) (layout-buffer-list-current state))))
  (define (update-layout! change)
    (set-box! buffers-state (layout-buffers-update-current (unbox buffers-state) change)))
  (define (focused-unit)
    (hash-ref panes (if (unbox float-shown) (float-active-id) (layout-focused-id (current-layout))) #f))

  (define (bars-key)
    (define state (unbox key-state-box))
    (list (if (member (key-state-layer state) (list "editor" "shell")) "write" (key-state-layer state)) (key-state-pending-text state)
          (key-state-pinned-flag state) (unbox screen-columns)
          (layout-buffers-names (unbox buffers-state)) (layout-buffers-current-index (unbox buffers-state)) (unbox shell-cwd)))
  (define (ask-bars key)
    (bars-link-ask! bars (list-ref key 0) session-name (list-ref key 3)
                    (list-ref key 1) (list-ref key 2) (list-ref key 4) (list-ref key 5) (list-ref key 6)))
  (define first-key (bars-key))
  (define first-rows (list "" ""))
  (hash-set! bar-cache first-key first-rows)
  (define bar-rows (box (decorate-bars first-rows)))

  (define (refresh-bars!)
    (define unit (focused-unit))
    (when unit
      (set-box! shell-cwd (shell-cwd-of (subprocess-pid (pane-link-process (pane-unit-link unit))))))
    (define key (bars-key))
    (define rows (ask-bars key))
    (hash-set! bar-cache key rows)
    (set-box! dirty #t)
    (when (and (equal? key (bars-key)) (not (equal? (decorate-bars rows) (unbox bar-rows))))
      (set-box! bar-rows (decorate-bars rows))
      (set-box! dirty #t)))
  (define (show-cached-bars!)
    (define rows (hash-ref bar-cache (bars-key) #f))
    (when rows (set-box! bar-rows (decorate-bars rows))))

  (define (region-rects)
    (layout-rects (current-layout) (unbox screen-columns) (max 1 (- (unbox screen-height) (length (unbox bar-rows))))))
  (define (rect-fits? rect)
    (and (>= (layout-rect-width rect) 3) (>= (layout-rect-height rect) 3)))
  (define (live-ids)
    (append-map (lambda (buffer) (layout-tab-ids (layout-buffer-layout buffer)))
                (layout-buffer-list-buffers (unbox buffers-state))))

  (define (start-output-thread! unit)
    (thread
     (lambda ()
       (let loop ([leftover (bytes)])
         (define chunk (pane-read-chunk (pane-unit-link unit)))
         (cond
           [(eof-object? chunk) (set-box! dead-panes (cons (pane-unit-id unit) (unbox dead-panes)))]
           [else
            (define-values (text kept) (decode-complete-prefix (bytes-append leftover chunk)))
            (call-with-semaphore lock (lambda () (pane-grid-feed! (pane-unit-grid unit) text)))
            (set-box! dirty #t)
            (loop kept)])))))
  (define (open-pane! id columns rows)
    (define unit (pane-unit-open id columns rows (unbox shell-cwd)))
    (hash-set! panes id unit)
    (start-output-thread! unit))
  (define (prune-panes!)
    (define live (live-ids))
    (for ([id (in-list (hash-keys panes))])
      (unless (or (memv id live) (< id 0))
        (pane-unit-close! (hash-ref panes id))
        (hash-remove! panes id))))

  (define (fit-panes!)
    (call-with-semaphore
     state-lock
     (lambda ()
       (prune-panes!)
       (for ([rect (in-list (region-rects))] #:when (rect-fits? rect))
         (define id (layout-rect-id rect))
         (define columns (- (layout-rect-width rect) 2))
         (define rows (- (layout-rect-height rect) 2))
         (define unit (hash-ref panes id #f))
         (cond
           [(not unit) (open-pane! id columns rows)]
           [else
            (define grid (pane-unit-grid unit))
            (unless (and (= columns (pane-grid-columns grid)) (= rows (pane-grid-height grid)))
              (call-with-semaphore lock (lambda () (pane-grid-resize! grid columns rows)))
              (pane-set-size! (pane-unit-link unit) columns rows))]))
       (fit-float!))))

  (define (reap-dead-panes!)
    (call-with-semaphore
     state-lock
     (lambda ()
       (define ids (filter (lambda (id) (hash-ref panes id #f)) (unbox dead-panes)))
       (set-box! dead-panes ids)
       (for ([id (in-list ids)])
         (define here (layout-tab-ids (current-layout)))
         (cond
           [(< id 0)
            (pane-unit-close! (hash-ref panes id))
            (hash-remove! panes id)
            (set-box! float-shown #f)
            (set-box! dirty #t)]
           [(<= (tile-count) 1) (semaphore-post finished)]
           [(memv id here)
            (if (pair? (cdr here))
                (update-layout! (lambda (layout) (layout-close (layout-focus-id layout id))))
                (set-box! buffers-state (layout-buffers-close (unbox buffers-state))))
            (set-box! dirty #t)]
           [else (void)]))
       (prune-panes!))))

  (define (paint-now!)
    (define text
      (call-with-semaphore
       state-lock
       (lambda ()
(sync-app-layer! key-state-box (focused-unit))
         (define focus-id (layout-focused-id (current-layout)))
         (define entries
           (for/list ([rect (in-list (region-rects))]
                      #:when (and (rect-fits? rect) (hash-ref panes (layout-rect-id rect) #f)))
             (define unit (hash-ref panes (layout-rect-id rect)))
             (append (list (layout-rect-x rect) (layout-rect-y rect) (layout-rect-width rect) (layout-rect-height rect)
                   (pane-unit-grid unit) (unbox (pane-unit-scroll unit)) (equal? (layout-rect-id rect) focus-id)) (if (equal? (layout-rect-id rect) focus-id) (let ([ns (layout-buffers-names (unbox buffers-state))] [ci (layout-buffers-current-index (unbox buffers-state))]) (list (tabs-for unit (string-join (for/list ([n (in-list ns)] [i (in-naturals)]) (string-append (if (eqv? i ci) "● " "○ ") n)) "  ")) (top-label "") (format "~a" (key-state-layer (unbox key-state-box))) (bottom-label (unbox screen-columns)))) (list)))))
         (call-with-semaphore lock (lambda () (compose-frame (unbox screen-columns) (unbox screen-height) (append (if (unbox float-shown) (map (lambda (entry) (list-set entry 6 #f)) entries) entries) (float-entries)) (unbox bar-rows)))))))
    (for ([rect (in-list (region-rects))])
      (define unit (hash-ref panes (layout-rect-id rect) #f))
      (when (and unit (hash-ref pane-grid-running (pane-unit-grid unit) #f))
        (pulse-rect! (car text) (unbox screen-columns) (unbox screen-height)
                     (length (unbox bar-rows)) (layout-rect-x rect) (layout-rect-y rect)
                     (layout-rect-width rect) (layout-rect-height rect)
                     (eqv? 2 (hash-ref pane-grid-running (pane-unit-grid unit) #f)))))
    (when (unbox quit-ask)
      (draw-quit-box! (car text) (unbox screen-columns) (unbox screen-height)))
    (write-string (screen-diff-cells! text (unbox screen-columns) (unbox screen-height)) (current-output-port))
    (flush-output (current-output-port)))

  (define (paint-loop)
    (let loop ([last-check 0.0])
      (sleep 0.02)
      (define now (current-inexact-milliseconds))
      (define checking (> (- now last-check) size-check-milliseconds))
      (when (pair? (unbox dead-panes)) (set-box! pane-grid-run-flag #f))
      (when (pair? (unbox dead-panes)) (reap-dead-panes!))
      (when (and (pane-grid-any-running?) (not (= (pulse-phase) (unbox pulse-last))))
        (set-box! pulse-last (pulse-phase))
        (set-box! dirty #t))
      (when checking
        (define-values (columns height) (terminal-size))
        (unless (and (= columns (unbox screen-columns)) (= height (unbox screen-height)))
          (set-box! screen-columns columns)
          (set-box! screen-height height)
          (show-cached-bars!)
          (set-box! dirty #t))
        (fit-panes!))
      (when (unbox dirty)
        (set-box! dirty #f)
        (paint-now!))
      (loop (if checking now last-check))))

  (define (bars-loop)
    (let loop ([last-key (bars-key)] [last-time 0.0])
      (sleep 0.05)
      (define key (bars-key))
      (define now (current-inexact-milliseconds))
      (cond
        [(or (not (equal? key last-key)) (> (- now last-time) bar-refresh-milliseconds))
         (refresh-bars!)
         (loop key now)]
        [else (loop last-key last-time)])))

  (define (splash-toggle!)
    (call-with-semaphore
     state-lock
     (lambda ()
       (if (and (unbox float-shown) (= (unbox float-index) 3))
           (set-box! float-shown #f)
           (when (file-exists? (string-append (or (getenv "HOME") "") "/.local/share/aiu-pm/prefix/aiu-splash/live/bin/aiu-splash")) (set-box! float-preset 80) (show-float! 3)))))
    (fit-panes!))
  (define (apply-scroll-command! command)
    (if (eq? command (quote splash))
        (splash-toggle!)
        (apply-scroll-command-pane! command)))
  (define (apply-scroll-command-pane! command)
    (call-with-semaphore
     state-lock
     (lambda ()
       (define unit (focused-unit))
       (when unit
         (define grid (pane-unit-grid unit))
         (define link (pane-unit-link unit))
         (call-with-semaphore
          lock
          (lambda ()
            (cond
              [(pane-grid-alternate grid)
               (write-bytes (scroll-command-bytes command) (pane-link-master-out link))
               (flush-output (pane-link-master-out link))]
              [else
               (define step (if (memq command (quote (page-up page-down))) (max 1 (quotient (pane-grid-height grid) 2)) 1))
               (define limit (length (pane-grid-history grid)))
               (define scroll (pane-unit-scroll unit))
               (set-box! scroll
                         (if (memq command (quote (line-up page-up)))
                             (min limit (+ (unbox scroll) step))
                             (max 0 (- (unbox scroll) step))))])))))))

  (define (apply-buffer-command! command)
    (call-with-semaphore
     state-lock
     (lambda ()
       (define state (unbox buffers-state))
       (set-box! buffers-state
                 (case command
                   [(previous) (layout-buffers-previous state)]
                   [(next) (layout-buffers-next state)]
                   [(close) (layout-buffers-close state)]
                   [else
                    (set-box! pane-counter (add1 (unbox pane-counter)))
                    (set-box! buffer-counter (add1 (unbox buffer-counter)))
                    (layout-buffers-add state (format "buffer ~a" (unbox buffer-counter)) (unbox pane-counter))])))))

  (define (split-pane! direction)
    (set-box! pane-counter (add1 (unbox pane-counter)))
    (define id (unbox pane-counter))
    (update-layout! (lambda (layout) (layout-split layout id direction))))
  (define (apply-pane-command! command)
    (case command
      [(focus-left) (update-layout! (lambda (layout) (layout-focus layout (quote left))))]
      [(focus-right) (update-layout! (lambda (layout) (layout-focus layout (quote right))))]
      [(focus-up) (update-layout! (lambda (layout) (layout-focus layout (quote up))))]
      [(focus-down) (update-layout! (lambda (layout) (layout-focus layout (quote down))))]
      [(split-right) (split-pane! (quote right))]
      [(split-down) (split-pane! (quote down))]
      [(float-toggle) (set-box! float-shown (not (unbox float-shown)))]
      [(float-todo) (show-float! 0)]
      [(float-journal) (show-float! 1)]
      [(float-notes) (show-float! 2)]
      [(float-size) (set-box! float-preset (float-next-share (unbox float-preset)))]
      [(float-grow) (set-box! float-preset (float-grow-share (unbox float-preset)))]
      [(float-shrink) (set-box! float-preset (float-shrink-share (unbox float-preset)))]
      [else (when (pair? (cdr (layout-tab-ids (current-layout)))) (update-layout! layout-close))]))

  (define (apply-buffer-keys! input)
    (cond
      [(string=? (key-state-layer (unbox key-state-box)) "buffer")
       (define-values (remaining commands) (split-buffer-keys input))
       (for ([command (in-list commands)]) (apply-buffer-command! command))
       (when (pair? commands) (fit-panes!))
       remaining]
      [else input]))
  (define (apply-pane-keys! input)
    (cond
      [(string=? (key-state-layer (unbox key-state-box)) "pane")
       (define-values (remaining commands) (split-pane-keys input))
       (call-with-semaphore state-lock (lambda () (for ([command (in-list commands)]) (apply-pane-command! command))))
       (when (pair? commands) (fit-panes!))
       remaining]
      [else input]))
  (define (apply-scroll-keys! input)
    (define state (unbox key-state-box))
    (cond
      [(and (string=? (key-state-layer state) "visual") (eq? (key-state-pending state) (quote none)))
       (define-values (remaining commands) (split-scroll-keys input))
       (for ([command (in-list commands)]) (apply-scroll-command! command))
       remaining]
      [else input]))

  (define startup-splash (box #f))
  (define paste-active (box #f))
  (define (key-loop)
    (define buffer (make-bytes 4096))
    (let loop ()
      (define amount (read-bytes-avail! buffer (current-input-port)))
      (when (and (unbox startup-splash) (not (eof-object? amount)))
        (set-box! startup-splash #f)
        (call-with-semaphore state-lock
          (lambda () (set-box! float-shown #f)))
        (fit-panes!)
        (set-box! dirty #t))
      (cond
        [(eof-object? amount) (semaphore-post finished)]
        [(and (unbox quit-ask) (> amount 0))
         (define b (bytes-ref buffer 0))
         (cond
           [(or (= b 13) (= b 10) (= b 32)) (semaphore-post finished)]
           [(or (= b 110) (= b 78))
            (set-box! quit-ask #f)
            (set-box! dirty #t)
            (loop)]
           [else (loop)])]
        [(and (getenv "AIU_PANE_PROGRAM")
              (> amount 0)
              (focused-unit)
              (or (unbox paste-active)
                  (regexp-match? #rx#"\e\\[200~" (subbytes buffer 0 amount))))
         (let ([chunk (subbytes buffer 0 amount)])
           (set-box! paste-active (not (regexp-match? #rx#"\e\\[201~" chunk)))
           (write-bytes chunk (pane-link-master-out (pane-unit-link (focused-unit))))
           (flush-output (pane-link-master-out (pane-unit-link (focused-unit)))))
         (loop)]
        [(and (getenv "AIU_PANE_PROGRAM")
              (> amount 0)
              (focused-unit)
              (string=? (key-state-layer (unbox key-state-box)) "visual")
              (eq? (key-state-pending (unbox key-state-box)) (quote none))
              (not (memv (bytes-ref buffer 0) (list 32 105 27 113))))
         (write-bytes (subbytes buffer 0 amount) (pane-link-master-out (pane-unit-link (focused-unit))))
         (flush-output (pane-link-master-out (pane-unit-link (focused-unit))))
         (loop)]
        
        [else
         (define layer-before (key-state-layer (unbox key-state-box)))
         (define-values (forwarded next-state quit?)
           (route-keys (unbox key-state-box)
                       (apply-pane-keys! (apply-buffer-keys! (apply-scroll-keys! (subbytes buffer 0 amount))))))
         (let ([was (key-state-layer (unbox key-state-box))] [now (key-state-layer next-state)])
             (cond
               [#f (void)]
               [(and (string=? now "pane") (eq? (key-state-pending next-state) (quote float))) (set-box! float-shown (not (unbox float-shown)))]))
           (set-box! key-state-box (if (and (string=? (key-state-layer next-state) "pane") (eq? (key-state-pending next-state) (quote float))) (key-state (if (unbox float-shown) "write" "visual") (quote none) (key-state-pinned next-state)) next-state))
         (define unit (focused-unit))
         (when (and unit (member (key-state-layer next-state) (list "write" "editor" "shell")))
           (set-box! (pane-unit-scroll unit) 0))
         (when (and (getenv "AIU_PANE_PROGRAM") (string=? layer-before "write") (regexp-match? #rx#"[\r\n]" (subbytes buffer 0 amount))) (set-box! key-state-box (key-state "visual" (quote none) (key-state-pinned (unbox key-state-box)))))
         (define sent (cond [(and (string=? layer-before "visual") (string=? (key-state-layer next-state) "write") (getenv "AIU_PANE_PROGRAM")) (bytes-append #"i" forwarded)] [(and (string=? layer-before "write") (string=? (key-state-layer next-state) "visual") (getenv "AIU_PANE_PROGRAM")) forwarded] [else forwarded]))
         (when (and unit (> (bytes-length sent) 0))
           (write-bytes sent (pane-link-master-out (pane-unit-link unit)))
           (flush-output (pane-link-master-out (pane-unit-link unit))))
         (show-cached-bars!)
         (set-box! dirty #t)
         (if quit? (begin (set-box! quit-ask #t) (set-box! dirty #t) (loop)) (loop))])))

  (set-box! pane-grid-quit-hook
            (lambda ()
              (set-box! quit-ask #t)
              (set-box! dirty #t)))
  (splash-toggle!)
  (set-box! startup-splash (unbox float-shown))
  (fit-panes!)
  (dynamic-wind
   (lambda ()
     (raw-mode)
     (system* stty-program "raw" "-echo")
     (write-string "\e[?2004h")
     (flush-output)
     (plumber-add-flush! (current-plumber) (lambda (h) (write-string "\e[?2004l") (flush-output)))
     (write-string "\u001b[?1049h\u001b[2J" (current-output-port))
     (flush-output (current-output-port)))
   (lambda ()
     (thread paint-loop)
     (thread bars-loop)
     (thread key-loop)
     (semaphore-wait finished))
   (lambda ()
     (write-string "\u001b[?25h\u001b[?1049l" (current-output-port))
     (flush-output (current-output-port))
     (restore-settings)
     (for ([unit (in-list (hash-values panes))]) (pane-unit-close! unit))
     (bars-link-close! bars))))

(provide run-multiplexer)

(module+ main (run-multiplexer))
