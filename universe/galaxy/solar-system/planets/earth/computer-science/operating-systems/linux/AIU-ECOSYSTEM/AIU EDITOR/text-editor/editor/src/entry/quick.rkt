#lang racket/base
;; One job: the quick screen, what the terminal shows in the first moments,
;; before the editor has loaded. It needs only racket/base, so it paints at
;; once. The keys typed while the editor loads wait in the terminal and are
;; read when the editor is ready. The terminal settings it changes are given
;; back when the program ends, whatever way it ends.

(provide quick-show
         quick-restore)

;; changed says whether this screen changed the terminal settings.
(define changed (box #f))

;; run-stty runs one shell line on the terminal the editor was started in and
;; answers what it printed.
(define (run-stty line)
  (define sh (find-executable-path "sh"))
  (if sh
      (with-handlers ([exn:fail? (lambda (why) "")])
        (let-values ([(proc out in err)
                      (subprocess #f (current-input-port) (quote stdout) sh "-c" line)])
          (let ([text (read-string 200 out)])
            (close-input-port out)
            (subprocess-wait proc)
            (if (eof-object? text) "" text))))
      ""))

;; size-of answers the rows and the columns the terminal said, or 24 and 80.
(define (size-of text)
  (define m (regexp-match #px"(\\d+)\\s+(\\d+)" text))
  (if m
      (values (string->number (cadr m)) (string->number (caddr m)))
      (values 24 80)))

;; head-of answers the first part of a file as text, or nothing when the file
;; cannot be read, so a new file shows an empty screen.
(define (head-of file)
  (with-handlers ([exn:fail? (lambda (why) "")])
    (call-with-input-file file
      (lambda (in)
        (let ([text (read-string 20000 in)])
          (if (eof-object? text) "" text))))))

;; fit answers one line cut to the width of the screen.
(define (fit line cols)
  (define clean (regexp-replace* #rx"\t" line "    "))
  (if (> (string-length clean) cols) (substring clean 0 cols) clean))

;; first-rows answers the first n lines of a list.
(define (first-rows lines n)
  (let loop ([rest lines] [left n] [out null])
    (if (or (null? rest) (<= left 0))
        (reverse out)
        (loop (cdr rest) (sub1 left) (cons (car rest) out)))))

;; frame answers the text that draws the first screen: the lines of the file
;; and a mode line that says the editor is loading.
(define (frame lines rows cols name)
  (define shown (first-rows lines (max 1 (- rows 1))))
  (define label (string-append " " name "  loading the editor"))
  (define mode
    (if (> (string-length label) cols)
        (substring label 0 cols)
        (string-append label (make-string (- cols (string-length label)) #\space))))
  (string-append "\u001b[?1049h\u001b[2J\u001b[H\u001b[?25l"
                 (apply string-append
                        (let loop ([rest shown] [out null])
                          (cond
                            [(null? rest) (reverse out)]
                            [else (loop (cdr rest)
                                        (cons (string-append (fit (car rest) cols)
                                                             (if (null? (cdr rest)) "" "\r\n"))
                                              out))])))
                 (format "\u001b[~a;1H\u001b[7m~a\u001b[27m" rows mode)))

;; quick-show paints the file at once and takes the keys off the screen: the
;; terminal does not echo them and does not wait for a return, so they queue
;; for the editor. With no file it paints the name of the home screen. Nothing
;; happens when the program is not on a terminal.
(define (quick-show file)
  (when (and (terminal-port? (current-input-port))
             (terminal-port? (current-output-port)))
    (define size (run-stty "stty -echo -icanon; stty size"))
    (set-box! changed #t)
    (plumber-add-flush! (current-plumber) (lambda (handle) (quick-restore)))
    (define-values (rows cols) (size-of size))
    (define lines
      (if file
          (regexp-split #rx"\n" (head-of file))
          (list "AIU DASHBOARD" "" "loading the home screen")))
    (write-string (frame lines rows cols (or file "AIU home")))
    (flush-output)))

;; quick-restore gives the terminal its echo and its line mode back, once.
(define (quick-restore)
  (when (unbox changed)
    (set-box! changed #f)
    (run-stty "stty echo icanon")))
