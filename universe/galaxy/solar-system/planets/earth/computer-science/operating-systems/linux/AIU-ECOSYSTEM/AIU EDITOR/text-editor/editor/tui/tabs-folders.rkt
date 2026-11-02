#lang racket/base
;; One job: the folder and name helpers of the tabs - last name, parent, labels, workspace root, project and the folders listed.

(require racket/list racket/string racket/path)

(provide tb-skipped tb-last tb-parent tb-labels tb-root tb-project tb-project-dir tb-dirs)

;; tb-skipped are the folder names the listing never shows.
(define tb-skipped (list "compiled" "node_modules" "target" "aiu-compiled"))

;; tb-last answers the last name of a path, or nothing when there is none.
(define (tb-last p)
  (cond
    [(not (or (string? p) (path? p))) ""]
    [else
     (define-values (base name dir?) (split-path (if (string? p) (string->path p) p)))
     (if (path? name) (path->string name) "")]))

;; tb-parent answers the folder of a path, or false at the top.
(define (tb-parent p)
  (define-values (base name dir?) (split-path (if (string? p) (string->path p) p)))
  (and (path? base) base))

;; tb-labels answers the name of each tab; two tabs with one name show their folder too.
(define (tb-labels files)
  (define names (map tb-last files))
  (for/list ([f (in-list files)] [n (in-list names)])
    (if (> (length (filter (lambda (x) (string=? x n)) names)) 1)
        (string-append (tb-last (tb-parent f)) "/" n)
        n)))

;; tb-root answers the workspace folder of a file: AIU_ROOT when it is set, else
;; the folder named AIU-ECOSYSTEM above the file, else the folder of the file.
(define (tb-root file)
  (define given (getenv "AIU_ROOT"))
  (cond
    [(and given (directory-exists? given)) (string->path given)]
    [else
     (let loop ([dir (tb-parent file)])
       (cond
         [(not dir) (or (tb-parent file) (current-directory))]
         [(string=? (tb-last dir) "AIU-ECOSYSTEM") dir]
         [else (loop (tb-parent dir))]))]))

;; tb-project answers the project of a file: the first folder under the root, or
;; the folder of the file when it is not under a folder of the root.
(define (tb-project file root)
  (define rel (find-relative-path root (string->path file)))
  (define parts (if (relative-path? rel) (explode-path rel) null))
  (if (and (> (length parts) 1) (path? (car parts)))
      (path->string (car parts))
      (tb-last (tb-parent file))))

;; tb-project-dir answers the folder of the project of a file: the folder named by
;; the project under the root, or the folder of the file when there is none.
(define (tb-project-dir file root)
  (define candidate (build-path root (tb-project file root)))
  (if (directory-exists? candidate)
      candidate
      (or (tb-parent file) (current-directory))))

;; tb-dirs answers the names of the folders in a folder, in order, without the
;; hidden ones and the skipped ones.
(define (tb-dirs dir)
  (with-handlers ([(lambda (e) #t) (lambda (e) null)])
    (sort (for/list ([e (in-list (directory-list dir))]
                     #:when (let ([n (path->string e)])
                              (and (directory-exists? (build-path dir e))
                                   (not (char=? (string-ref n 0) #\.))
                                   (not (member n tb-skipped)))))
            (path->string e))
          string<?)))
