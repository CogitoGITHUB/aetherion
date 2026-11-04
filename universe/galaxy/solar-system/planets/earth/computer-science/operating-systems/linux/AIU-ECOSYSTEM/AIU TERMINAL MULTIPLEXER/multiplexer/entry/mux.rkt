#lang racket/base
(require racket/system
         "../pane/pane-pty.rkt" "../pane/pane-grid.rkt" "../pane/pane-text-decode.rkt"
         "../pane/pane-keys.rkt" "../frame/frame-bars.rkt" "../frame/frame-paint.rkt"
         "../machine/terminal.rkt")

(define layer-name "insert")
(define session-name "shell")
(define stty-program "/usr/bin/stty")

(define (run-multiplexer)
  (define-values (first-columns first-height) (terminal-size))
  (define bars (bars-link-open))
  (define screen-columns (box first-columns))
  (define screen-height (box first-height))
  (define bar-rows (box (bars-link-ask! bars layer-name session-name first-columns)))
  (define inner-columns (frame-inner-columns first-columns))
  (define inner-rows (frame-inner-rows first-height (length (unbox bar-rows))))
  (define grid (make-pane-grid inner-columns inner-rows))
  (define link (pane-open (or (getenv "SHELL") "/bin/sh") (list) inner-columns inner-rows))
  (define lock (make-semaphore 1))
  (define dirty (box #t))
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
         (paint-screen-string grid (unbox bar-rows) (unbox screen-columns) (unbox screen-height)))))
    (write-string text (current-output-port))
    (flush-output (current-output-port)))

  (define (paint-loop)
    (let loop ()
      (sleep 0.03)
      (define-values (columns height) (terminal-size))
      (unless (and (= columns (unbox screen-columns)) (= height (unbox screen-height)))
        (set-box! screen-columns columns)
        (set-box! screen-height height)
        (set-box! bar-rows (bars-link-ask! bars layer-name session-name columns))
        (set-box! dirty #t))
      (fit-pane-to-screen!)
      (when (unbox dirty)
        (set-box! dirty #f)
        (paint-now!))
      (loop)))

  (define (bars-loop)
    (let loop ()
      (sleep 1)
      (define rows (bars-link-ask! bars layer-name session-name (unbox screen-columns)))
      (unless (equal? rows (unbox bar-rows))
        (set-box! bar-rows rows)
        (set-box! dirty #t))
      (loop)))

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

  (define (key-loop)
    (define buffer (make-bytes 4096))
    (let loop ([state (quote plain)])
      (define amount (read-bytes-avail! buffer (current-input-port)))
      (cond
        [(eof-object? amount) (semaphore-post finished)]
        [else
         (define-values (forwarded next-state quit?) (route-keys state (subbytes buffer 0 amount)))
         (when (> (bytes-length forwarded) 0)
           (write-bytes forwarded (pane-link-master-out link))
           (flush-output (pane-link-master-out link)))
         (if quit? (semaphore-post finished) (loop next-state))])))

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
