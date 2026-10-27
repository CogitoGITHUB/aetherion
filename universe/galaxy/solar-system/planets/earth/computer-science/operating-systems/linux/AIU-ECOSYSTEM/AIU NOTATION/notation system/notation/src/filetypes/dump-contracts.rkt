#lang racket/base
;; dump-contracts.rkt -- writes the contracts of every file type to one tab-separated file for the Rust view command.
;; Called by: tools/see/aiu (refresh-contracts). Argument: the path of the file to write.
(require racket/string "filetypes.rkt")

;; The path to write, from the command line.
(define out-path (vector-ref (current-command-line-arguments) 0))

;; One contract as a line: type, rule or question, section, block, then name and argument, or the question text.
(define (contract-line type c)
  (string-join (map (lambda (x) (format "~a" x)) (cons type c)) "\t"))

(with-output-to-file out-path #:exists 'truncate
  (lambda ()
    (for ([(name t) (in-hash (load-file-types))])
      (for ([c (in-list (contracts-of name))])
        (displayln (contract-line name c))))))
