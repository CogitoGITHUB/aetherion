#lang racket/base

(define notation-tail (list "text-editor" "notation" "target" "debug" "notation"))

(define (notation-bin-from dir)
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
