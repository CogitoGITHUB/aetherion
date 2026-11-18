#lang racket/base
(require racket/file racket/string)
(provide theme-sgr theme-rgb theme-stamp theme-refresh! theme-reset)

(define theme-reset "\e[0m")
(define defaults
  (make-hash (list (cons "text" "white") (cons "dim" "#6e6e6e")
                   (cons "error" "red") (cons "bg" "none"))))
(define names
  (make-hash (list (cons "black" 30) (cons "red" 31) (cons "green" 32)
                   (cons "yellow" 33) (cons "blue" 34)
                   (cons "magenta" 35) (cons "cyan" 36)
                   (cons "white" 97) (cons "gray" 90))))
(define rgbs
  (make-hash (list (cons "black" (list 0 0 0))
                   (cons "red" (list 220 40 40))
                   (cons "green" (list 40 200 40))
                   (cons "yellow" (list 220 200 40))
                   (cons "blue" (list 60 100 230))
                   (cons "magenta" (list 200 60 200))
                   (cons "cyan" (list 40 200 200))
                   (cons "white" (list 255 255 255))
                   (cons "gray" (list 110 110 110)))))

(define cache (make-hash))
(define stamp (box #f))
(define checked (box 0.0))
(define version (box 0))

(define (theme-dir)
  (define env (getenv "AIU_THEME_DIR"))
  (cond
    [(and env (directory-exists? env)) env]
    [else
     (define f (build-path (find-system-path (quote home-dir)) ".config" "aiu" "theme-dir"))
     (and (file-exists? f)
          (let ([d (string-trim (file->string f))])
            (and (directory-exists? d) d)))]))

(define (theme-path)
  (define d (theme-dir))
  (define act (and d (build-path d "active")))
  (define nm (and act (file-exists? act) (string-trim (file->string act))))
  (and nm (regexp-match? #px"^[A-Za-z0-9_-]+$" nm)
       (build-path d (string-append nm ".theme"))))

(define (stamp-of p)
  (and p (file-exists? p)
       (list p (file-or-directory-modify-seconds p) (file-size p))))

(define (parse-line s)
  (define m (regexp-match #px"^\\s*([a-z-]+)\\s*=\\s*(\\S+)\\s*$" s))
  (and m (cons (cadr m) (caddr m))))

(define (theme-refresh!)
  (define p (with-handlers ([void (lambda (e) #f)]) (theme-path)))
  (define s (with-handlers ([void (lambda (e) #f)]) (stamp-of p)))
  (unless (equal? s (unbox stamp))
    (set-box! stamp s)
    (hash-clear! cache)
    (when s
      (with-handlers ([void void])
        (for ([ln (in-list (file->lines p))])
          (define kv (parse-line ln))
          (when kv (hash-set! cache (car kv) (cdr kv))))))
    (set-box! version (add1 (unbox version)))))

(define (maybe-refresh!)
  (define now (current-inexact-milliseconds))
  (when (> (- now (unbox checked)) 150.0)
    (set-box! checked now)
    (theme-refresh!)))

(define (theme-stamp)
  (maybe-refresh!)
  (unbox version))

(define (role-value role)
  (maybe-refresh!)
  (hash-ref cache role (lambda () (hash-ref defaults role "none"))))

(define (hex->rgb v)
  (define m (regexp-match
             #px"^#([0-9a-fA-F]{2})([0-9a-fA-F]{2})([0-9a-fA-F]{2})$" v))
  (and m (map (lambda (x) (string->number x 16)) (cdr m))))

(define (rgb-of v) (or (hex->rgb v) (hash-ref rgbs v #f)))

(define (theme-rgb role)
  (or (rgb-of (role-value role))
      (rgb-of (hash-ref defaults role "none"))))

(define (code v bg?)
  (cond
    [(string=? v "none") ""]
    [(hex->rgb v)
     => (lambda (c)
          (format "\e[~a;2;~a;~a;~am" (if bg? 48 38)
                  (car c) (cadr c) (caddr c)))]
    [(hash-ref names v #f)
     => (lambda (n) (format "\e[~am" (if bg? (+ n 10) n)))]
    [else #f]))

(define (theme-sgr role)
  (define bg? (string=? role "bg"))
  (or (code (role-value role) bg?)
      (code (hash-ref defaults role "none") bg?)
      ""))
