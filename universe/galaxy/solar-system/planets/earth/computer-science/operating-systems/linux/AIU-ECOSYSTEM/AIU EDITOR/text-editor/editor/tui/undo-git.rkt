#lang racket/base
;; One job: the git calls and the small helpers of the undo layer: running git, times, cuts, lists and byte lengths.
(require racket/list racket/string racket/port)

;; undo-git-exe is the git program, or false.
(define undo-git-exe (find-executable-path "git"))

;; undo-slurp reads a port to the end and answers the text.
(define (undo-slurp in)
  (let ([out (open-output-string)])
    (let loop ()
      (let ([s (read-string 4096 in)])
        (unless (eof-object? s) (write-string s out) (loop))))
    (get-output-string out)))

;; undo-git runs git in a folder and answers what it printed, or false when it failed.
(define (undo-git dir . args)
  (and undo-git-exe
       (with-handlers ([void (lambda (e) #f)])
         (let-values ([(sp out in err)
                       (apply subprocess #f #f #f undo-git-exe "-C" dir "-c" "core.quotepath=off" args)])
           (close-output-port in)
           (let* ([o (undo-slurp out)] [e (undo-slurp err)])
             (close-input-port out)
             (close-input-port err)
             (subprocess-wait sp)
             (and (zero? (subprocess-status sp)) o))))))

;; undo-two writes a number with two digits.
(define (undo-two n) (if (< n 10) (string-append "0" (number->string n)) (number->string n)))

;; undo-when writes a time in seconds as month-day hour:minute.
(define (undo-when secs)
  (let ([d (seconds->date secs)])
    (string-append (undo-two (date-month d)) "-" (undo-two (date-day d)) " "
                   (undo-two (date-hour d)) ":" (undo-two (date-minute d)))))

;; undo-cut cuts a text to at most n characters.
(define (undo-cut s n) (if (> (string-length s) n) (substring s 0 n) s))

;; undo-first answers the first n items of a list.
(define (undo-first n l) (if (or (<= n 0) (null? l)) (list) (cons (car l) (undo-first (sub1 n) (cdr l)))))

;; undo-index answers the place of an item in a list, or false.
(define (undo-index id lst)
  (let loop ([l lst] [i 0])
    (cond [(null? l) #f]
          [(equal? (car l) id) i]
          [else (loop (cdr l) (add1 i))])))

;; undo-blen answers the length of a text in bytes.
(define (undo-blen s) (bytes-length (string->bytes/utf-8 s)))


(provide undo-git-exe undo-slurp undo-git undo-two undo-when undo-cut undo-first undo-index undo-blen)
