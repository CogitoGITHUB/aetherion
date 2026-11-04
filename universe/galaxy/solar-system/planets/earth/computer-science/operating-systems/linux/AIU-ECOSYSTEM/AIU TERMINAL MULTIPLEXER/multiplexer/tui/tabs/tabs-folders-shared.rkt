#lang racket/base

(require racket/list racket/string racket/path)

(provide tabs-skipped tabs-last tabs-parent tabs-labels tabs-root tabs-project tabs-project-dir tabs-dirs)

;; tabs-skipped are the folder names the listing never shows.
(define tabs-skipped (list "compiled" "node_modules" "target" "aiu-compiled"))

(define (tabs-last p)
  (cond
    [(not (or (string? p) (path? p))) ""]
    [else
     (define-values (base name dir?) (split-path (if (string? p) (string->path p) p)))
     (if (path? name) (path->string name) "")]))

(define (tabs-parent p)
  (define-values (base name dir?) (split-path (if (string? p) (string->path p) p)))
  (and (path? base) base))

(define (tabs-labels files)
  (define names (map tabs-last files))
  (for/list ([f (in-list files)] [n (in-list names)])
    (if (> (length (filter (lambda (x) (string=? x n)) names)) 1)
        (string-append (tabs-last (tabs-parent f)) "/" n)
        n)))

(define (tabs-root file)
  (define given (getenv "AIU_ROOT"))
  (cond
    [(and given (directory-exists? given)) (string->path given)]
    [else
     (let loop ([dir (tabs-parent file)])
       (cond
         [(not dir) (or (tabs-parent file) (current-directory))]
         [(string=? (tabs-last dir) "AIU-ECOSYSTEM") dir]
         [else (loop (tabs-parent dir))]))]))

(define (tabs-project file root)
  (define rel (find-relative-path root (string->path file)))
  (define parts (if (relative-path? rel) (explode-path rel) null))
  (if (and (> (length parts) 1) (path? (car parts)))
      (path->string (car parts))
      (tabs-last (tabs-parent file))))

(define (tabs-project-dir file root)
  (define candidate (build-path root (tabs-project file root)))
  (if (directory-exists? candidate)
      candidate
      (or (tabs-parent file) (current-directory))))

;; hidden ones and the skipped ones.
(define (tabs-dirs dir)
  (with-handlers ([(lambda (e) #t) (lambda (e) null)])
    (sort (for/list ([e (in-list (directory-list dir))]
                     #:when (let ([n (path->string e)])
                              (and (directory-exists? (build-path dir e))
                                   (not (char=? (string-ref n 0) #\.))
                                   (not (member n tabs-skipped)))))
            (path->string e))
          string<?)))
