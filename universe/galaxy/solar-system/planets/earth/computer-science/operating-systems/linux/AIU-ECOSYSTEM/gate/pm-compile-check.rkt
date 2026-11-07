#lang racket/base
(require racket/list racket/path racket/runtime-path compiler/cm)
(define-runtime-path here "..")
(define eco (simplify-path (path->complete-path here)))
(define src (build-path eco "AIU-OS" "AIU-PM" "package-manager" "src"))
(define roots (list (build-path (find-system-path (quote home-dir)) "aiu-compiled") (quote same)))
(define files
  (sort (for/list ([p (in-directory src)]
                   #:when (regexp-match? #rx"[.]rkt$" (path->string p))
                   #:unless (regexp-match? #rx"/compiled/" (path->string p)))
          (path->string p))
        string<?))
(define (first-line message) (car (regexp-split #rx"\n" message)))
(define failures
  (parameterize ([current-compiled-file-roots roots]
                 [current-load/use-compiled (make-compilation-manager-load/use-compiled-handler)]
                 [current-namespace (make-base-namespace)])
    (for/fold ([found (list)]) ([file (in-list files)])
      (with-handlers ([(lambda (e) #t)
                       (lambda (e)
                         (append found (list (cons file (first-line (if (exn? e) (exn-message e) "raised"))))))])
        (dynamic-require (string->path file) (void))
        found))))
(cond
  [(null? failures) (printf "PASS pm-compile: ~a package manager files compile\n" (length files))]
  [else
   (printf "FAIL pm-compile: ~a of ~a package manager files do not compile\n" (length failures) (length files))
   (for ([f (in-list (take failures (min 15 (length failures))))]) (printf "  ~a: ~a\n" (car f) (cdr f)))
   (exit 1)])
