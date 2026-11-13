#lang racket/base

(define notation-tail (list "AIU NOTATION" "notation" "target" "debug" "notation"))

(define (notation-bin-search dir)
  (define named (getenv "AIU_NOTATION_BIN"))
  (if (and named (not (string=? named "")) (file-exists? named))
      named
      (let loop ([d (path->complete-path dir)] [k 0])
        (define c (apply build-path d notation-tail))
        (cond [(file-exists? c) (path->string c)]
              [(> k 8) #f]
              [else (let-values ([(base name dir?) (split-path d)])
                      (if (path? base) (loop base (add1 k)) #f))]))))

(provide notation-tail notation-bin-from)
(define (notation-bin-from dir)
  (define home (getenv "HOME"))
  (define xdg (getenv "XDG_DATA_HOME"))
  (define data (if (and xdg (not (string=? xdg ""))) xdg (and home (string-append home "/.local/share"))))
  (define pm (and data (string-append data "/aiu-pm/prefix/aiu-notation/current/bin/notation")))
  (or (notation-bin-search dir) (and pm (file-exists? pm) pm)))
