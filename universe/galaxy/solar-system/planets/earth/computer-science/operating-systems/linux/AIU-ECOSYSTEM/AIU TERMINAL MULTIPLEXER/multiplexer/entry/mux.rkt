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
(define (top-label)
  (define d (dev-text))
  (string-append "server " (unbox server-state)
                 (if (string=? d "") "" (string-append "  " d))))
(define (bottom-label layer)
  (string-append (clock-stamp 50 #t #t) "\u0001" layer))

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
    (define unit (pane-unit-open id columns rows (unbox shell-cwd)))
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
         (define focus-id (layout-focused-id (current-layout)))
         (define entries
           (for/list ([rect (in-list (region-rects))]
                      #:when (and (rect-fits? rect) (hash-ref panes (layout-rect-id rect) #f)))
             (define unit (hash-ref panes (layout-rect-id rect)))
             (append (list (layout-rect-x rect) (layout-rect-y rect) (layout-rect-width rect) (layout-rect-height rect)
                   (pane-unit-grid unit) (unbox (pane-unit-scroll unit)) (equal? (layout-rect-id rect) focus-id)) (if (equal? (layout-rect-id rect) focus-id) (let ([ns (layout-buffers-names (unbox buffers-state))] [ci (layout-buffers-current-index (unbox buffers-state))]) (list (string-join (for/list ([n (in-list ns)] [i (in-naturals)]) (string-append (if (eqv? i ci) "● " "○ ") n)) "  ") (top-label) (string-append "● " (list-ref ns ci)) (bottom-label (format "~a" (key-state-layer (unbox key-state-box)))))) (list)))))
         (call-with-semaphore lock (lambda () (compose-frame (unbox screen-columns) (unbox screen-height) (append (if (unbox float-shown) (map (lambda (entry) (list-set entry 6 #f)) entries) entries) (float-entries)) (unbox bar-rows)))))))
    (write-string (screen-diff-cells! text (unbox screen-columns) (unbox screen-height)) (current-output-port))
    (flush-output (current-output-port)))

  (define (paint-loop)
    (let loop ([last-check 0.0])
      (sleep 0.02)
      (define now (current-inexact-milliseconds))
      (define checking (> (- now last-check) size-check-milliseconds))
      (when (pair? (unbox dead-panes)) (reap-dead-panes!))
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

  (define (apply-scroll-command! command)
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

  (define paste-active (box #f))
  (define (key-loop)
    (define buffer (make-bytes 4096))
    (let loop ()
      (define amount (read-bytes-avail! buffer (current-input-port)))
      (cond
        [(eof-object? amount) (semaphore-post finished)]
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
              (not (memv (bytes-ref buffer 0) (list 32 105 27))))
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
         (if quit? (semaphore-post finished) (loop))])))

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
