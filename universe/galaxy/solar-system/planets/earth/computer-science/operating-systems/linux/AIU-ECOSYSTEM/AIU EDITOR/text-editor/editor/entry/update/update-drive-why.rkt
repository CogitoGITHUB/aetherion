#lang racket/base
;; One job: the lines that explain a failed test: the error source, the last frame and the screen seen.
(require racket/system racket/string racket/list racket/file racket/path "update-table.rkt" "update-screen.rkt" "update-evidence.rkt")

;; wrap-text cuts one line into pieces of at most 90 characters.
(define (wrap-text l)
  (if (<= (string-length l) 90) (list l) (cons (substring l 0 90) (wrap-text (substring l 90)))))

;; err-where answers the lines that name an err- code on the screen, the source file and line that holds it and the lines around it.
(define (err-where scr)
  (define m (regexp-match #px"err-[a-z]+(-[a-z]+)*" scr))
  (cond
    [(not m) (list)]
    [else
     (define name (car m))
     (define root (path->string (build-path editor-root "editor")))
     (define rkts (with-handlers ([void (lambda (e) (list))]) (find-files (lambda (p) (regexp-match? #rx"[.]rkt$" (path->string p))) (build-path editor-root "editor"))))
     (define hit
       (for/or ([p (in-list rkts)])
         (define ls (with-handlers ([void (lambda (e) (list))]) (file->lines p)))
         (for/first ([l (in-list ls)] [i (in-naturals 0)] #:when (regexp-match? (regexp (string-append "\"" (regexp-quote name) "\"")) l))
           (list p ls i))))
     (if hit
         (append (list (string-append "    error " name " comes from " (substring (path->string (car hit)) (string-length root)) " line " (number->string (+ 1 (caddr hit))) ":"))
                 (for/list ([l (in-list (let* ([ls (cadr hit)] [i (caddr hit)] [lo (max 0 (- i 4))] [hi (min (length ls) (+ i 5))]) (take (drop ls lo) (- hi lo))))])
                   (string-append "    e " (let ([t (string-trim l)]) (if (> (string-length t) 70) (substring t 0 70) t)))))
         (list (string-append "    error " name " shown on screen, but no source file holds that name")))]))

;; diagnose answers the lines that explain a failed test: exit code, mid frame, last frame.
(define (diagnose code-file out out1)
  (define code (with-handlers ([void (lambda (e) "unknown")]) (string-trim (file->string code-file))))
  (define raw (with-handlers ([void (lambda (e) #"")]) (file->bytes out)))
  (define frame (with-handlers ([void (lambda (e) "")]) (plain-screen (last-frame (bytes->string/utf-8 raw #\?)))))
  (define tail (reverse (first-n (reverse (string-split frame "\n" #:trim? #f)) 10)))
  (append
   (list (string-append "    cause: exit code " code (if (equal? code "124") " = killed, the editor did not quit after q within 15 s" ""))
         (string-append "    mid frame: " (if (file-exists? out1) "saved" "MISSING, the editor produced nothing in 4 s"))
         "    last frame at the end:")
   (map (lambda (l) (string-append "    > " l)) (apply append (map wrap-text tail)))))

;; seen-lines answers the lines that show a failed test what the screen held, with row numbers, and the file head when a file expectation failed.
(define (seen-lines shown verdicts file-text)
  (append (list "    screen seen:")
          (apply append (for/list ([l (in-list shown)] [i (in-naturals 1)]) (wrap-text (format "    ~a ~a" i l))))
          (if (ormap (lambda (v) (and (not (car v)) (regexp-match? #rx"^file " (cadr v)))) verdicts)
              (cons "    file head:" (map (lambda (l) (string-append "    f " l)) (apply append (map wrap-text (first-n (string-split (visible file-text) "\n" #:trim? #f) 6)))))
              (list))))


(provide wrap-text err-where diagnose seen-lines)
