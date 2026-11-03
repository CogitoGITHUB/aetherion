#lang racket/base

(provide quick-show
         quick-restore)

(define changed (box #f))

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

(define (size-of text)
  (define m (regexp-match #px"(\\d+)\\s+(\\d+)" text))
  (if m
      (values (string->number (cadr m)) (string->number (caddr m)))
      (values 24 80)))

(define (head-of file)
  (with-handlers ([exn:fail? (lambda (why) "")])
    (call-with-input-file file
      (lambda (in)
        (let ([text (read-string 20000 in)])
          (if (eof-object? text) "" text))))))

(define (fit line cols)
  (define clean (regexp-replace* #rx"\t" line "    "))
  (if (> (string-length clean) cols) (substring clean 0 cols) clean))

(define (first-rows lines n)
  (let loop ([rest lines] [left n] [out null])
    (if (or (null? rest) (<= left 0))
        (reverse out)
        (loop (cdr rest) (sub1 left) (cons (car rest) out)))))

(define (frame lines rows cols name)
  (define shown (first-rows lines (max 1 (- rows 1))))
  (define label (string-append " " name ""))
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

(require "../notation/location.rkt")

(define (notation-path)
  (define s (notation-bin-from (current-directory)))
  (and s (string->path s)))

(define (boxed-lines file cols)
  (with-handlers ([exn:fail? (lambda (why) #f)])
    (define bin (notation-path))
    (and bin (file-exists? bin)
         (let-values ([(proc out in err) (subprocess #f #f (current-error-port) bin "view" (if (path? file) (path->string file) file) "--width" (number->string cols))])
           (close-output-port in)
           (let ([text (let loop ([acc null]) (let ([b (read-string 4096 out)]) (if (eof-object? b) (apply string-append (reverse acc)) (loop (cons b acc)))))])
             (close-input-port out)
             (subprocess-wait proc)
             (and (zero? (subprocess-status proc)) (not (string=? (regexp-replace* #px"\\s" text "") ""))
                  (regexp-split #rx"\n" text)))))))

(define (quick-show file)
  (when (and (terminal-port? (current-input-port))
             (terminal-port? (current-output-port)))
    (define size (run-stty "stty -echo -icanon; stty size"))
    (set-box! changed #t)
    (plumber-add-flush! (current-plumber) (lambda (handle) (quick-restore)))
    (define-values (rows cols) (size-of size))
    (define lines
      (if file
          (or (and (regexp-match? #rx"[.]aiu$" (if (path? file) (path->string file) file)) (boxed-lines file cols)) (regexp-split #rx"\n" (head-of file)))
          (list "AIU EDITOR" "" "opening the page")))
    (write-string (frame lines rows cols (or file "AIU editor")))
    (flush-output)))

(define (quick-restore)
  (when (unbox changed)
    (set-box! changed #f)
    (run-stty "stty echo icanon")))