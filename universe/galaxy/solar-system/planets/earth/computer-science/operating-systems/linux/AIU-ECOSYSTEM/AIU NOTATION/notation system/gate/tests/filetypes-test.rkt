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
  (regexp-match? (regexp-quote word) (regexp-replace* #px"[[:space:]]+" text " ")))

;; run-checks is the one entry the test runner calls.
(define (run-base-checks)
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

;; box-page writes one page to a temporary file, runs the boxed viewer on it with the flags, and
;; answers the exit code and everything the viewer printed.
(define (box-page text flags)
  (define file (make-temporary-file "aiu-box-~a.aiu"))
  (display-to-file text file #:exists (quote truncate))
  (putenv "AIU_NOTATION_BIN" (path->string (binary)))
  (putenv "LC_ALL" "C.UTF-8")
  (define out (open-output-string))
  (define code
    (parameterize ([current-output-port out]
                   [current-error-port out])
      (apply system*/exit-code (binary) "view" (path->string file) flags)))
  (delete-file file)
  (values code (get-output-string out)))

;; check-boxes checks the boxed viewer: every block in a box of its own, the contracts band at
;; the top, and each contract on the box it judges.
(define (check-boxes)
  (define long (word-paragraph 130))
  (define short (contract-paragraph "Text."))
  (define wide (list "--plain" "--width" "80"))
  (define wide-c (list "--plain" "--contracts" "--width" "80"))
  (let-values ([(code text) (box-page (contract-page long) wide-c)])
    (check-equal? code 0 text)
    (check-true (has-word? "CONTRACTS" text) text)
    (check-true (has-word? "RULE BROKEN" text) text)
    (check-true (has-word? "130 words" text) text)
    (check-true (has-word? "section 1" text) text)
    (check-true (has-word? "rules broken: 1" text) text)
    (check-false (has-word? "missing: code" text) text))
  (let-values ([(code text) (box-page (contract-page long) wide)])
    (check-true (has-word? "paragraph" text) text)
    (check-false (has-word? "CONTRACTS" text) text)
    (check-false (has-word? "RULE BROKEN" text) text))
  (let-values ([(code text) (box-page (contract-page short) wide-c)])
    (check-true (has-word? "OPEN QUESTION" text) text)
    (check-true (has-word? "holds: max-words 120" text) text)
    (check-false (has-word? "RULE BROKEN" text) text))
  (let-values ([(code text) (box-page "title start\nkind: decision\nD\ntitle end\n\nsection start\ntitle start\nContext\ntitle end\nparagraph start\nText.\nparagraph end\nsection end\n" wide-c)])
    (check-true (has-word? "missing: paragraph in section Decision" text) text)
    (check-false (has-word? "missing: code" text) text))
  (let-values ([(code text) (box-page (typed-page "default" short) wide-c)])
    (check-true (has-word? "rules broken: 0" text) text))
  (let-values ([(code text) (box-page (string-append "title start\nA test page\ntitle end\n\n" short) wide-c)])
    (check-true (has-word? "no contract applies" text) text)
    (check-true (has-word? "paragraph" text) text)))

;; run-checks is the one entry the test runner calls: the file type checks, then the
;; contract checks.
(define (run-checks)
  (run-base-checks)
  (check-contracts)
  (check-type-contracts)
  (check-viewer)
  (check-viewer-contracts)
  (check-boxes))

;; contract-section writes one section of a decision page: its title block, then the body.
(define (contract-section title body)
  (string-append "section start\ntitle start\n" title "\ntitle end\n" body "section end\n\n"))

;; contract-paragraph writes one paragraph block holding the text.
(define (contract-paragraph text)
  (string-append "paragraph start\n" text "\nparagraph end\n"))

;; contract-page writes a complete decision page whose Context section holds the given body.
(define (contract-page context-body)
  (string-append "title start\nkind: decision\nD-001 A test decision\ntitle end\n\n"
                 (contract-section "Context" context-body)
                 (contract-section "Options" (contract-paragraph "Text."))
                 (contract-section "Decision" (contract-paragraph "Text."))
                 (contract-section "Consequences" (contract-paragraph "Text."))))

;; check-contracts checks the contracts of the decision type: a clean page, a broken rule,
;; a missing declaration, and that questions appear only when AIU_QUESTIONS is 1.
(define (check-contracts)
  (define short (contract-paragraph "Text."))
  (define long (contract-paragraph (apply string-append (for/list ([i (in-range 130)]) "word "))))
  (define plain-code "code start\nx(1)\ncode end\n")
  (define lang-code "code start\nlanguage: racket\nx(1)\ncode end\n")
  (let-values ([(code text) (check-page (contract-page short))])
    (check-equal? code 0 text)
    (check-false (has-word? "question-unverified" text) text))
  (let-values ([(code text) (check-page (contract-page long))])
    (check-equal? code 1 text)
    (check-true (has-word? "rule-violated" text) text))
  (let-values ([(code text) (check-page (contract-page plain-code))])
    (check-equal? code 1 text)
    (check-true (has-word? "rule-violated" text) text))
  (let-values ([(code text) (check-page (contract-page lang-code))])
    (check-equal? code 0 text))
  (putenv "AIU_QUESTIONS" "1")
  (let-values ([(code text) (check-page (contract-page short))])
    (check-equal? code 1 text)
    (check-true (has-word? "question-unverified" text) text))
  (environment-variables-set! (current-environment-variables) #"AIU_QUESTIONS" #f))

;; word-paragraph writes a paragraph block of n words.
(define (word-paragraph n)
  (contract-paragraph (apply string-append (for/list ([i (in-range n)]) "word "))))

;; typed-page writes a page of the given kind: its title block, then the body.
(define (typed-page kind body)
  (string-append "title start\nkind: " kind "\nA test page\ntitle end\n\n" body))

;; sectioned-body writes one section for each title; the section named long holds 300 words.
(define (sectioned-body titles long)
  (apply string-append
         (for/list ([t (in-list titles)])
           (contract-section t (if (equal? t long) (word-paragraph 300) (contract-paragraph "Text."))))))

;; expect-clean checks that a page of the kind has no findings.
(define (expect-clean kind body)
  (let-values ([(code text) (check-page (typed-page kind body))])
    (check-equal? code 0 text)))

;; expect-rule checks that a page of the kind breaks a rule.
(define (expect-rule kind body)
  (let-values ([(code text) (check-page (typed-page kind body))])
    (check-equal? code 1 text)
    (check-true (has-word? "rule-violated" text) text)))

;; expect-questions checks that a page of the kind reports unverified questions, and only
;; while AIU_QUESTIONS is 1.
(define (expect-questions kind body)
  (putenv "AIU_QUESTIONS" "1")
  (let-values ([(code text) (check-page (typed-page kind body))])
    (check-equal? code 1 text)
    (check-true (has-word? "question-unverified" text) text))
  (environment-variables-set! (current-environment-variables) #"AIU_QUESTIONS" #f))

;; check-type-contracts checks that every type carries contracts, then one clean page, one
;; broken rule and, where the type has questions, one report for each type but decision.
(define (check-type-contracts)
  (for ([(name t) (in-hash (load-file-types))])
    (check-true (pair? (contracts-of name)) (format "~a carries no contracts" name)))
  (define short (contract-paragraph "Text."))
  (define long (word-paragraph 300))
  (define plain-code "code start\nx(1)\ncode end\n")
  (define plan-titles (list "Goal" "Steps" "Done when" "Open questions"))
  (define research-titles
    (list "Abstract" "Introduction" "Methods" "Results" "Discussion" "References"))
  (define module-titles (list "Purpose" "Code"))
  (expect-clean "plan" (sectioned-body plan-titles #f))
  (expect-rule "plan" (sectioned-body plan-titles "Goal"))
  (expect-questions "plan" (sectioned-body plan-titles #f))
  (expect-clean "research" (sectioned-body research-titles #f))
  (expect-rule "research" (sectioned-body research-titles "Abstract"))
  (expect-questions "research" (sectioned-body research-titles #f))
  (expect-clean "module" (sectioned-body module-titles #f))
  (expect-rule "module" (sectioned-body module-titles "Purpose"))
  (expect-rule "module" (string-append (contract-section "Purpose" short)
                                       (contract-section "Code" plain-code)))
  (expect-questions "module" (sectioned-body module-titles #f))
  (expect-clean "note" short)
  (expect-rule "note" long)
  (expect-rule "note" plain-code)
  (expect-clean "book" short)
  (expect-rule "book" long)
  (expect-questions "book" short)
  (expect-clean "journal" short)
  (expect-rule "journal" long)
  (expect-questions "journal" short)
  (expect-clean "todo" short)
  (expect-rule "todo" long)
  (expect-questions "todo" short)
  (expect-clean "default" short)
  (expect-rule "default" long)
  (expect-rule "default" plain-code))

;; view-page writes one page to a temporary file, runs the viewer on it with the flags, and
;; answers the exit code and everything the viewer printed.
(define (view-page text flags)
  (define file (make-temporary-file "aiu-view-~a.aiu"))
  (display-to-file text file #:exists 'truncate)
  (putenv "AIU_NOTATION_BIN" (path->string (binary)))
  (putenv "LC_ALL" "C.UTF-8")
  (define out (open-output-string))
  (define code
    (parameterize ([current-output-port out]
                   [current-error-port out])
      (apply system*/exit-code (binary) "view"
             (path->string file)
             (cons "--flat" flags))))
  (delete-file file)
  (values code (get-output-string out)))

;; check-viewer checks the contracts panel of the viewer: it shows broken rules and open
;; questions, says so when there are none, and is absent without the flag.
(define (check-viewer)
  (define long (word-paragraph 130))
  (define short (contract-paragraph "Text."))
  (let-values ([(code text) (view-page (contract-page long) (list "--plain" "--contracts"))])
    (check-true (has-word? "RULE BROKEN" text) text)
    (check-true (has-word? "130 words" text) text))
  (let-values ([(code text) (view-page (contract-page long) (list "--plain"))])
    (check-false (has-word? "RULE BROKEN" text) text)
    (check-false (has-word? "Contracts" text) text))
  (let-values ([(code text) (view-page (contract-page short) (list "--plain" "--contracts"))])
    (check-true (has-word? "OPEN QUESTION" text) text)
    (check-false (has-word? "RULE BROKEN" text) text))
  (let-values ([(code text) (view-page (typed-page "default" short) (list "--plain" "--contracts"))])
    (check-true (has-word? "rules broken: 0" text) text)))

;; aiu-see-page writes one page to a temporary file, runs "aiu see" on it through Nushell
;; with the flags, and answers the exit code and everything it printed. Nushell refuses a
;; working directory that ends in a slash, which Racket hands to a child process, so bash
;; first moves to the physical directory and only then starts Nushell.
(define (aiu-see-page text flags)
  (define file (make-temporary-file "aiu-aiusee-~a.aiu"))
  (display-to-file text file #:exists 'truncate)
  (putenv "AIU_NOTATION_BIN" (path->string (binary)))
  (putenv "AIU_RACKET" (path->string (find-exe)))
  (putenv "LC_ALL" "C.UTF-8")
  (define nu (find-executable-path "nu"))
  (define bash (find-executable-path "bash"))
  (define out (open-output-string))
  (define code
    (if (and nu bash)
        (parameterize ([current-output-port out]
                       [current-error-port out])
          (apply system*/exit-code bash
                 "-c" "cd \"$(pwd -P)\" && exec \"$@\""
                 "bash" nu
                 (build-path project-root "tools" "see" "aiu")
                 "see" (path->string file) flags))
        -1))
  (delete-file file)
  (values code (get-output-string out)))

;; check-viewer-contracts checks the full contract list of the panel: every contract with its
;; state, a page without a kind, and the flag passed through the aiu command.
(define (check-viewer-contracts)
  (define long (word-paragraph 130))
  (define short (contract-paragraph "Text."))
  (let-values ([(code text) (view-page (contract-page long) (list "--plain" "--contracts"))])
    (check-true (has-word? "BROKEN, line" text) text)
    (check-true (has-word? "holds in 1 block" text) text)
    (check-true (has-word? "no matching block" text) text)
    (check-true (has-word? "not verified (line" text) text))
  (let-values ([(code text) (view-page (contract-page short) (list "--plain" "--contracts"))])
    (check-true (has-word? "holds in 1 block" text) text)
    (check-false (has-word? "BROKEN" text) text))
  (let-values ([(code text) (view-page (string-append "title start\nA test page\ntitle end\n\n" short)
                                       (list "--plain" "--contracts"))])
    (check-true (has-word? "no kind: line" text) text)
    (check-true (has-word? "no contract applies" text) text))
  (let-values ([(code text) (aiu-see-page (contract-page long) (list "--plain" "--contracts"))])
    (check-true (has-word? "RULE BROKEN" text) text))
  (let-values ([(code text) (aiu-see-page (contract-page long) (list "--plain"))])
    (check-true (has-word? "Text." text) text)
    (check-false (has-word? "Contracts" text) text)))
