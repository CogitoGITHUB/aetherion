#lang racket/base
(require racket/list racket/string racket/port)

(define undo-git-exe (find-executable-path "git"))

(define (undo-slurp in)
  (let ([out (open-output-string)])
    (let loop ()
      (let ([s (read-string 4096 in)])
        (unless (eof-object? s) (write-string s out) (loop))))
    (get-output-string out)))

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

(define (undo-two n) (if (< n 10) (string-append "0" (number->string n)) (number->string n)))

(define (undo-when secs)
  (let ([d (seconds->date secs)])
    (string-append (undo-two (date-month d)) "-" (undo-two (date-day d)) " "
                   (undo-two (date-hour d)) ":" (undo-two (date-minute d)))))

(define (undo-cut s n) (if (> (string-length s) n) (substring s 0 n) s))

(define (undo-first n l) (if (or (<= n 0) (null? l)) (list) (cons (car l) (undo-first (sub1 n) (cdr l)))))

(define (undo-index id lst)
  (let loop ([l lst] [i 0])
    (cond [(null? l) #f]
          [(equal? (car l) id) i]
          [else (loop (cdr l) (add1 i))])))

(define (undo-blen s) (bytes-length (string->bytes/utf-8 s)))


(provide undo-git-exe undo-slurp undo-git undo-two undo-when undo-cut undo-first undo-index undo-blen)
