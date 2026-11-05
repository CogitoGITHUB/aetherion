#lang racket/base
(require racket/system
         "../pane/pane-pty.rkt" "../pane/pane-grid.rkt" "../pane/pane-text-decode.rkt"
         "../pane/pane-keys.rkt" "../pane/pane-scroll-keys.rkt" "../pane/pane-buffer-keys.rkt" "../tui/layout/layout-buffers-shared.rkt" "../frame/frame-bars.rkt" "../frame/frame-paint.rkt"
         "../machine/terminal.rkt")

(define session-name "shell")
(define stty-program "/usr/bin/stty")
(define bar-refresh-milliseconds 1000)
(define size-check-milliseconds 400)

(define (run-multiplexer)
  (define-values (first-columns first-height) (terminal-size))
  (define bars (bars-link-open))
  (define key-state-box (box (initial-key-state)))
  (define screen-columns (box first-columns))
  (define screen-height (box first-height))
  (define buffers-state (box (layout-buffers-new "main" 1)))
  (define bar-cache (make-hash))
  (define shell-cwd (box ""))
  (define (bars-key)
    (define state (unbox key-state-box))
    (list (key-state-layer state) (key-state-pending-text state)
          (key-state-pinned-flag state) (unbox screen-columns)
          (layout-buffers-names (unbox buffers-state)) (layout-buffers-current-index (unbox buffers-state)) (unbox shell-cwd)))
  (define (ask-bars key)
    (bars-link-ask! bars (list-ref key 0) session-name (list-ref key 3)
                    (list-ref key 1) (list-ref key 2) (list-ref key 4) (list-ref key 5) (list-ref key 6)))
  (define first-key (bars-key))
  (define first-rows (ask-bars first-key))
  (hash-set! bar-cache first-key first-rows)
  (define bar-rows (box first-rows))
  (define dirty (box #t))
  (define scroll-offset (box 0))
  (define (refresh-bars!)
    (set-box! shell-cwd (shell-cwd-of (subprocess-pid (pane-link-process link))))
    (define key (bars-key))
    (define rows (ask-bars key))
    (hash-set! bar-cache key rows)
    (when (and (equal? key (bars-key)) (not (equal? rows (unbox bar-rows))))
      (set-box! bar-rows rows)
      (set-box! dirty #t)))
  (define (show-cached-bars!)
    (define rows (hash-ref bar-cache (bars-key) #f))
    (when rows (set-box! bar-rows rows)))
  (define inner-columns (frame-inner-columns first-columns))
  (define inner-rows (frame-inner-rows first-height (length (unbox bar-rows))))
  (define grid (make-pane-grid inner-columns inner-rows))
  (define link (pane-open (path->string (or (find-executable-path "nu") (error "nu not found"))) (list) inner-columns inner-rows))
  (define lock (make-semaphore 1))
  (define finished (make-semaphore 0))
  (set-pane-grid-reply!
   grid
   (lambda (answer)
     (write-bytes answer (pane-link-master-out link))
     (flush-output (pane-link-master-out link))))

  (define (fit-pane-to-screen!)
    (define wanted-columns (frame-inner-columns (unbox screen-columns)))
    (define wanted-rows (frame-inner-rows (unbox screen-height) (length (unbox bar-rows))))
    (when (and (> wanted-columns 0) (> wanted-rows 0)
               (or (not (= wanted-columns (pane-grid-columns grid)))
                   (not (= wanted-rows (pane-grid-height grid)))))
      (call-with-semaphore lock (lambda () (pane-grid-resize! grid wanted-columns wanted-rows)))
      (pane-set-size! link wanted-columns wanted-rows)))

  (define (paint-now!)
    (define text
      (call-with-semaphore
       lock
       (lambda ()
         (paint-screen-string grid (unbox bar-rows) (unbox screen-columns) (unbox screen-height) (unbox scroll-offset)))))
    (write-string text (current-output-port))
    (flush-output (current-output-port)))

  (define (paint-loop)
    (let loop ([last-check 0.0])
      (sleep 0.02)
      (define now (current-inexact-milliseconds))
      (define checking (> (- now last-check) size-check-milliseconds))
      (when checking
        (define-values (columns height) (terminal-size))
        (unless (and (= columns (unbox screen-columns)) (= height (unbox screen-height)))
          (set-box! screen-columns columns)
          (set-box! screen-height height)
          (show-cached-bars!)
          (set-box! dirty #t))
        (fit-pane-to-screen!))
      (when (unbox dirty)
        (set-box! dirty #f)
        (paint-now!))
      (loop (if checking now last-check))))

  (define (bars-loop)
    (let loop ([last-key (bars-key)] [last-time (current-inexact-milliseconds)])
      (sleep 0.05)
      (define key (bars-key))
      (define now (current-inexact-milliseconds))
      (cond
        [(or (not (equal? key last-key)) (> (- now last-time) bar-refresh-milliseconds))
         (refresh-bars!)
         (loop key now)]
        [else (loop last-key last-time)])))

  (define (shell-output-loop)
    (let loop ([leftover (bytes)])
      (define chunk (pane-read-chunk link))
      (cond
        [(eof-object? chunk) (semaphore-post finished)]
        [else
         (define-values (text kept) (decode-complete-prefix (bytes-append leftover chunk)))
         (call-with-semaphore lock (lambda () (pane-grid-feed! grid text)))
         (set-box! dirty #t)
         (loop kept)])))

  (define (apply-scroll-command! command)
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
          (set-box! scroll-offset
                    (if (memq command (quote (line-up page-up)))
                        (min limit (+ (unbox scroll-offset) step))
                        (max 0 (- (unbox scroll-offset) step))))]))))

  (define buffer-tab-counter (box 1))

  (define (apply-buffer-command! command)
    (define state (unbox buffers-state))
    (set-box! buffers-state
              (case command
                [(previous) (layout-buffers-previous state)]
                [(next) (layout-buffers-next state)]
                [(close) (layout-buffers-close state)]
                [else
                 (set-box! buffer-tab-counter (add1 (unbox buffer-tab-counter)))
                 (layout-buffers-add state (format "buffer ~a" (unbox buffer-tab-counter)) (unbox buffer-tab-counter))])))

  (define (apply-buffer-keys! input)
    (cond
      [(string=? (key-state-layer (unbox key-state-box)) "buffer")
       (define-values (remaining commands) (split-buffer-keys input))
       (for ([command (in-list commands)]) (apply-buffer-command! command))
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

  (define (key-loop)
    (define buffer (make-bytes 4096))
    (let loop ()
      (define amount (read-bytes-avail! buffer (current-input-port)))
      (cond
        [(eof-object? amount) (semaphore-post finished)]
        [else
         (define-values (forwarded next-state quit?)
           (route-keys (unbox key-state-box) (apply-buffer-keys! (apply-scroll-keys! (subbytes buffer 0 amount)))))
         (set-box! key-state-box next-state)
                        (when (string=? (key-state-layer next-state) "write") (set-box! scroll-offset 0))
         (when (> (bytes-length forwarded) 0)
           (write-bytes forwarded (pane-link-master-out link))
           (flush-output (pane-link-master-out link)))
         (show-cached-bars!)
         (set-box! dirty #t)
         (if quit? (semaphore-post finished) (loop))])))

  (dynamic-wind
   (lambda ()
     (raw-mode)
     (system* stty-program "raw" "-echo")
     (write-string "\u001b[?1049h\u001b[2J" (current-output-port))
     (flush-output (current-output-port)))
   (lambda ()
     (thread paint-loop)
     (thread bars-loop)
     (thread shell-output-loop)
     (thread key-loop)
     (semaphore-wait finished))
   (lambda ()
     (write-string "\u001b[?25h\u001b[?1049l" (current-output-port))
     (flush-output (current-output-port))
     (restore-settings)
     (pane-close! link)
     (bars-link-close! bars))))

(module+ main (run-multiplexer))
