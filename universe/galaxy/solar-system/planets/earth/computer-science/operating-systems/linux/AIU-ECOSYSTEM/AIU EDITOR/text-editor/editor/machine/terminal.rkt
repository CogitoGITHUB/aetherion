#lang racket/base

(require racket/file
         racket/port
         racket/string
         racket/system
         "directories-shared.rkt")

(define stty "/usr/bin/stty")

(define settings-file
  (build-path (state-dir) "terminal-settings"))

(define (saved-settings)
  (if (file-exists? settings-file)
      (let ([text (file->string settings-file)])
        (string-trim text))
      #f))

(define (current-settings)
  (let* ([out (open-output-string)]
         [in (open-input-string "")])
    (parameterize ([current-output-port out])
      (system* stty "-g"))
    (string-trim (get-output-string out))))

(define (save-settings)
  (ensure-dir (state-dir))
  (call-with-output-file settings-file
    (lambda (port) (display (current-settings) port))
    #:exists 'truncate)
  (saved-settings))

(define (restore-settings)
  (define settings (saved-settings))
  (when settings
    (system* stty settings)
    (delete-file settings-file))
  settings)

(define (raw-mode)
  (define settings (save-settings))
  (system* stty "-icanon" "-echo" "min" "1" "time" "0")
  settings)

(define window-cache (box #f))
(define window-cache-ms 2000)

(define (terminal-size)
  (define kept (unbox window-cache))
  (cond
    [(and kept
          (< (- (current-inexact-milliseconds) (cdr kept)) window-cache-ms))
     (values (car (car kept)) (cdr (car kept)))]
    [else
     (define-values (columns rows) (ask-stty-for-size))
     (set-box! window-cache (cons (cons columns rows) (current-inexact-milliseconds)))
     (values columns rows)]))

(define (ask-stty-for-size)
  (define out (with-output-to-string (lambda () (system* stty "size"))))
  (define parts (string-split (string-trim out)))
  (cond
    [(and (= (length parts) 2)
          (string->number (car parts))
          (string->number (cadr parts)))
     (define columns (string->number (cadr parts)))
     (define rows (string->number (car parts)))
     (if (or (<= columns 0) (<= rows 0))
         (values 80 24)
         (values columns rows))]
    [else (values 80 24)]))

(define (size-forget!) (set-box! window-cache #f))

(provide stty
         settings-file
         saved-settings
         current-settings
         save-settings
         restore-settings
         raw-mode
         terminal-size
         size-forget!)
