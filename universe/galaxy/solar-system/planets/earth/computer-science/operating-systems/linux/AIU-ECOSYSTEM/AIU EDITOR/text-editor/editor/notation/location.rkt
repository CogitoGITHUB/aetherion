#lang racket/base
;; One job: where the AIU NOTATION binary is, so the one place that knows the repo layout is this file.

;; notation-tail is the path of the notation binary under the folder that holds the AIU NOTATION repo.
(define notation-tail (list "AIU NOTATION" "notation system" "notation" "target" "debug" "notation"))

;; notation-bin-from answers the notation binary as a string, from AIU_NOTATION_BIN when it names a file, else by walking up from a folder, or false.
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
