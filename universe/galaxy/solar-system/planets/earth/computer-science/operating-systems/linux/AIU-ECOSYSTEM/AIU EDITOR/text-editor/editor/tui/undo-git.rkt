#lang racket/base
;; One job: the git calls and the small helpers of the undo layer: running git, times, cuts, lists and byte lengths.
(require racket/list racket/string racket/port)

;; ud-git-exe is the git program, or false.
(define ud-git-exe (find-executable-path "git"))

;; ud-slurp reads a port to the end and answers the text.
(define (ud-slurp in)
  (let ([out (open-output-string)])
    (let loop ()
      (let ([s (read-string 4096 in)])
        (unless (eof-object? s) (write-string s out) (loop))))
    (get-output-string out)))

;; ud-git runs git in a folder and answers what it printed, or false when it failed.
(define (ud-git dir . args)
  (and ud-git-exe
       (with-handlers ([void (lambda (e) #f)])
         (let-values ([(sp out in err)
                       (apply subprocess #f #f #f ud-git-exe "-C" dir "-c" "core.quotepath=off" args)])
           (close-output-port in)
           (let* ([o (ud-slurp out)] [e (ud-slurp err)])
             (close-input-port out)
             (close-input-port err)
             (subprocess-wait sp)
             (and (zero? (subprocess-status sp)) o))))))

;; ud-two writes a number with two digits.
(define (ud-two n) (if (< n 10) (string-append "0" (number->string n)) (number->string n)))

;; ud-when writes a time in seconds as month-day hour:minute.
(define (ud-when secs)
  (let ([d (seconds->date secs)])
    (string-append (ud-two (date-month d)) "-" (ud-two (date-day d)) " "
                   (ud-two (date-hour d)) ":" (ud-two (date-minute d)))))

;; ud-cut cuts a text to at most n characters.
(define (ud-cut s n) (if (> (string-length s) n) (substring s 0 n) s))

;; ud-first answers the first n items of a list.
(define (ud-first n l) (if (or (<= n 0) (null? l)) (list) (cons (car l) (ud-first (sub1 n) (cdr l)))))

;; ud-index answers the place of an item in a list, or false.
(define (ud-index id lst)
  (let loop ([l lst] [i 0])
    (cond [(null? l) #f]
          [(equal? (car l) id) i]
          [else (loop (cdr l) (add1 i))])))

;; ud-blen answers the length of a text in bytes.
(define (ud-blen s) (bytes-length (string->bytes/utf-8 s)))


(provide ud-git-exe ud-slurp ud-git ud-two ud-when ud-cut ud-first ud-index ud-blen)
