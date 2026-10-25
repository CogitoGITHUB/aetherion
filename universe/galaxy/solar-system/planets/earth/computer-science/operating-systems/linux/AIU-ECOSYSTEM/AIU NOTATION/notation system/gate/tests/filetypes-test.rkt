#lang racket/base
;; filetypes-test.rkt -- the checks for file types: the loader, the type modules, and
;; the findings the checker gives for a page that declares kind:.
;; Called by: gate/test-runner.rkt, through the run-tests stage of the gate.
(require (for-syntax racket/base)
         rackunit
         racket/file
         racket/port
         racket/runtime-path
         racket/system
         compiler/find-exe
         "../../notation/src/filetypes/filetypes.rkt")

(provide run-checks)

;; The project root: two folders above this file (gate/tests/).
(define-runtime-path project-root "../..")

;; The Rust binary the checker reads pages with.
(define (binary)
  (build-path project-root "notation" "target" "debug" "notation"))

;; check-page writes one page to a temporary file, runs the checker on it, and answers
;; the exit code and everything the checker printed.
(define (check-page text)
  (define file (make-temporary-file "aiu-test-~a.aiu"))
  (display-to-file text file #:exists 'truncate)
  (putenv "AIU_NOTATION_BIN" (path->string (binary)))
  (putenv "LC_ALL" "C.UTF-8")
  (define out (open-output-string))
  (define code
    (parameterize ([current-output-port out]
                   [current-error-port out])
      (system*/exit-code (find-exe)
                         (build-path project-root "notation" "src" "entry" "cli.rkt")
                         "check" file)))
  (delete-file file)
  (values code (get-output-string out)))

;; has-word? answers whether the checker's output names a finding.
(define (has-word? word text)
  (regexp-match? (regexp-quote word) text))

;; run-checks is the one entry the test runner calls.
(define (run-checks)
  (check-true (file-exists? (binary)) "the Rust binary is not built: run cargo build first")
  (define types (load-file-types))
  (check-true (hash-has-key? types "book") "the book type is missing")
  (check-true (hash-has-key? types "default") "the default type is missing")
  (check-equal? (length (type-modules)) (hash-count types) "two type modules share a name")
  (for ([(name t) (in-hash types)])
    (check-equal? (file-type-name t) name "a type's name must match what it loads under")
    (check-true (string? (file-type-description t)) (format "~a has no description" name))
    (check-true (or (not (file-type-allowed-blocks t))
                    (andmap string? (file-type-allowed-blocks t)))
                (format "~a: allowed blocks must be #f or a list of names" name)))
  (check-false (file-type-named "no-such-type"))
  (let-values ([(code text)
                (check-page "title start\nkind: book\nMy book\ntitle end\n\nparagraph start\nFine.\nparagraph end\n")])
    (check-equal? code 0 text))
  (let-values ([(code text)
                (check-page "title start\nkind: book\nMy book\ntitle end\n\nheading start\nlevel: 1\nNo\nheading end\n")])
    (check-equal? code 1 text)
    (check-true (has-word? "block-not-in-type" text) text))
  (let-values ([(code text)
                (check-page "title start\nkind: zzz\nMy page\ntitle end\n")])
    (check-equal? code 1 text)
    (check-true (has-word? "unknown-file-type" text) text))
  (let-values ([(code text)
                (check-page "title start\nMy page\ntitle end\n\nheading start\nlevel: 1\nFine\nheading end\n")])
    (check-equal? code 0 text))
  (let-values ([(code text)
                (check-page "title start\nkind: default\nMy default\ntitle end\n\nheading start\nlevel: 1\nFine\nheading end\n")])
    (check-equal? code 0 text)))
