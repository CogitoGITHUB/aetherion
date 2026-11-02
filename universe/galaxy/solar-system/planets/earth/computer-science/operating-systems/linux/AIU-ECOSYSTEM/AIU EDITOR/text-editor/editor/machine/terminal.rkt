#lang racket/base
;; One job: the terminal — the raw mode, the settings that were found,
;; and the bytes that arrive. Registered in plan/package-tree.org; lands
;; with TODO item 6.
;;
;; The terminal is put in raw mode so the keys arrive one at a time and
;; nothing waits for a return. The settings that were found are saved
;; FIRST and put back at the end, so the terminal is given back exactly
;; as it was found. A run that was killed leaves the settings on disk,
;; and the next run gives the terminal back before it goes raw again.
;;
;; There is NO timer here. A wait ends on an action: the read waits for
;; the next byte and the reader decides when a key is whole. The kitty
;; keyboard protocol's flags are what tell a key apart — the terminal is
;; asked to report the escape codes it would otherwise swallow.
;;
;; The stty program is the one on this phone, and it is named by its
;; whole path so the program never depends on the PATH.

(require racket/file
         racket/port
         racket/string
         racket/system
         "directories.rkt")

;; stty is the program that reads and writes the settings of the
;; terminal.
(define stty "/usr/bin/stty")

;; settings-file is where the settings of the terminal are kept, so a run
;; that was killed can give the terminal back at the next run.
(define settings-file
  (build-path (state-dir) "terminal-settings"))

;; saved-settings answers the settings that were saved, or nothing when
;; none were saved yet.
(define (saved-settings)
  (if (file-exists? settings-file)
      (let ([text (file->string settings-file)])
        (string-trim text))
      #f))

;; current-settings answers the settings of the terminal as they are now.
;; The settings are one line of text, and the terminal says them itself.
(define (current-settings)
  (let* ([out (open-output-string)]
         [in (open-input-string "")])
    (parameterize ([current-output-port out])
      (system* stty "-g"))
    (string-trim (get-output-string out))))

;; save-settings writes the settings of the terminal to the settings
;; file, so they can be put back later.
(define (save-settings)
  (ensure-dir (state-dir))
  (call-with-output-file settings-file
    (lambda (port) (display (current-settings) port))
    #:exists 'truncate)
  (saved-settings))

;; restore-settings gives the terminal back the settings that were
;; saved, and forgets them: the terminal is as it was found.
(define (restore-settings)
  (define settings (saved-settings))
  (when settings
    (system* stty settings)
    (delete-file settings-file))
  settings)

;; raw-mode puts the terminal in raw mode: the keys arrive one at a time
;; and nothing waits for a return. It answers the settings it saved, so
;; the caller can put them back.
(define (raw-mode)
  (define settings (save-settings))
  (system* stty "-icanon" "-echo" "min" "1" "time" "0")
  settings)

;; The terminal, for the entry above it.
;; terminal-size answers the columns and the rows of the terminal, or 80 by
;; 24 when the terminal does not say. stty is asked, because this Racket
;; cannot ask the terminal itself.
;;
;; The answer is kept for a short while, because the question is a program
;; start and a key must not pay one. A window is not asked about again
;; while the person is pressing keys; a pause of a couple of seconds — the
;; pause before a resize is noticed, if the window is ever resized — asks
;; again, and the frame is drawn to the window it is in.
(define window-cache (box #f))
;; window-cache-ms is part of this module.
(define window-cache-ms 2000)

;; terminal-size is part of this module.
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

;; ask-stty-for-size is the question itself: one stty, read, parsed, and
;; 80 by 24 when the terminal does not say.
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

(provide stty
         settings-file
         saved-settings
         current-settings
         save-settings
         restore-settings
         raw-mode
         terminal-size)
