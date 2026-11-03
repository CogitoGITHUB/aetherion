#lang racket/base
;; One job: running one test file on a copy of its page and answering the verdict.
(require racket/system racket/string racket/list racket/file racket/path "update-table.rkt" "update-screen.rkt" "update-evidence.rkt" "update-drive-live.rkt" "update-drive-pty.rkt" "update-drive-why.rkt" "update-module.rkt")

;; run-test runs one test file: a module test when the file names a module, a key test otherwise.
(define (run-test path)
  (if (pair? (line-values (test-lines path) "module")) (run-module-test path) (run-key-test path)))

;; run-key-test runs one test file on a copy of its page in a temporary folder; answers (name seconds ok? detail-lines).
(define (run-key-test path)
  (define lines (test-lines path))
  (define name (let ([v (line-values lines "test")]) (if (pair? v) (car v) "unnamed")))
  (define page (let ([v (line-values lines "file")]) (if (pair? v) (car v) "test.aiu")))
  (define input
    (apply string-append
           (for/list ([l (in-list lines)])
             (cond [(string-prefix? l "keys ") (apply string-append (map key-bytes (string-split (substring l 5))))]
                   [(string-prefix? l "type ") (substring l 5)]
                   [else ""]))))
  (define dir (make-temporary-file "aiutd-test~a" (quote directory)))
  (define copy (build-path dir page))
  (copy-file (build-path editor-root page) copy)
  (define keys-file (path->string (build-path dir "keys.bin")))
  (define out (path->string (build-path dir "out.bin")))
  (define out1 (path->string (build-path dir "mid.bin")))
  (call-with-output-file keys-file #:exists (quote truncate) (lambda (o) (write-string input o)))
  (when (member "repo git" lines) (begin (capture dir (find-executable-path "git") (list "init" "-q")) (capture dir (find-executable-path "git") (list "add" "-A")) (capture dir (find-executable-path "git") (list "-c" "user.name=t" "-c" "user.email=t@t" "commit" "-q" "-m" "init"))))
  (define trace-start (trace-size))
  (define t0 (current-inexact-milliseconds))
  (define chunks
    (apply append
           (for/list ([l (in-list lines)])
             (cond [(string-prefix? l "keys ") (map key-bytes (string-split (substring l 5)))]
                   [(string-prefix? l "type ") (list (substring l 5))]
                   [else (list)]))))
  (define code-file (path->string (build-path dir "code.txt")))
  (drive-editor dir (path->string copy) chunks out out1 code-file)
  (define seconds (begin (live "driver returned") (secs t0)))
  (define raw (if (file-exists? out) (file->bytes out) #""))
  (live "plain screen")
  (define rawf (last-frame (bytes->string/utf-8 raw #\?)))
  (define screen (plain-screen rawf))
  (define file-text (with-handlers ([void (lambda (e) "")]) (file->string copy)))
  (live "judging")
  (define verdicts
    (for/list ([l (in-list lines)] #:when (string-prefix? l "expect "))
      (judge l screen file-text seconds rawf)))
  (define ok? (and (pair? verdicts) (andmap car verdicts)))
  (live "diagnosing")
  (define evidence (if (or (not ok?) (member "record" lines)) (evidence-lines dir out lines verdicts screen trace-start) (list)))
  (set-box! last-evidence evidence)
  (define why-full (if ok? (list) (append (filter (lambda (l) (not (regexp-match? #rx"^    >" l))) (append (diagnose code-file out out1) (err-where screen))) (trace-since trace-start) (list "    mode after each key:") (map (lambda (l) (car (regexp-split #rx" [|] " l))) (key-modes dir (string-split (string-join (line-values lines "keys") " ")))) (append (if (member "repo git" lines) (cons "    undo commits of the temp repo:" (map (lambda (l) (string-append "    c " l)) (first-n (string-split (let-values ([(c o) (capture dir (find-executable-path "git") (list "log" "--format=%h %s" "aiu-undo"))]) o) "\n") 6))) (list)) (list "    file head, first 6 lines:")) (map (lambda (l) (string-append "    f " l)) (apply append (map wrap-text (first-n (string-split (visible file-text) "\n" #:trim? #f) 6)))))))
  (with-handlers ([void void])
    (display-to-file screen (build-path (find-system-path (quote home-dir)) (string-append ".aiu-last-test-" name ".txt")) #:exists (quote truncate)))
  (define why (let ([c (filter (lambda (l) (or (regexp-match? #rx"^    (error|e) " l) (and (regexp-match? #rx"cause:" l) (not (regexp-match? #rx"exit code 0" l))))) why-full)]) (if (pair? c) c (list))))
  (when (member "record" lines)
    (with-handlers ([void void])
      (display-to-file screen (build-path (find-system-path (quote home-dir)) ".aiu-record-screen.txt") #:exists (quote truncate))
      (display-to-file rawf (build-path (find-system-path (quote home-dir)) ".aiu-record-raw.txt") #:exists (quote truncate))
      (display-to-file file-text (build-path (find-system-path (quote home-dir)) ".aiu-record-file.txt") #:exists (quote truncate))))
  (when (getenv "AIU_FRAMES")
    (with-handlers ([void void])
      (let* ([all (if (file-exists? out) (bytes->string/utf-8 (file->bytes out) #\?) "")]
             [parts (regexp-split (regexp-quote "\u001b[?2026h") all)]
             [rows (for/list ([p (in-list parts)] [i (in-naturals)])
                     (let ([t (plain-screen p)])
                       (format "frame ~a len ~a visual-general ~a modes-popup ~a grey ~a white ~a" i (string-length t) (regexp-match? #rx"visual general" t) (regexp-match? #rx"modes . switch" t) (length (regexp-match* #rx"\u001b\\[90m" p)) (length (regexp-match* #rx"\u001b\\[97m" p)))))])
        (display-to-file (string-join rows "\n") (build-path (find-system-path (quote home-dir)) "aiu-frames-summary.txt") #:exists (quote truncate)))))
  (live "deleting temp folder")
  (remove-tree dir)
  (live "building report")
  (define shown (first-n (string-split screen "\n" #:trim? #f) 24))
  (list name seconds ok?
        (append (list (string-append "    keys " (string-join (line-values lines "keys") " ")))
                (for/list ([v (in-list verdicts)] #:unless (car v))
                  (string-append "    " (if (car v) "ok   " "FAIL ") (cadr v))) (if ok? (list) (append (seen-lines shown verdicts file-text) evidence))
                why)))

;; remove-tree deletes a folder with rm, which survives a git process still writing into it, and never raises.
(define (remove-tree p . rest)
  (with-handlers ([void void])
    (parameterize ([current-output-port (open-output-string)] [current-error-port (open-output-string)])
      (system* (find-executable-path "rm") "-r" "-f" (if (path? p) (path->string p) p)))))


(provide run-test remove-tree run-tests-parallel cores)

(require (only-in racket/future processor-count) (only-in racket/system system*) (only-in racket/string string-trim))

;; cores answers how many cores this process may really use: nproc knows the limit, processor-count only sees the machine.
(define (cores)
  (with-handlers ([void (lambda (x) (processor-count))])
    (let ([o (open-output-string)])
      (parameterize ([current-output-port o]) (system* (find-executable-path "nproc")))
      (or (string->number (string-trim (get-output-string o))) (processor-count)))))

;; run-tests-parallel runs key tests one after another in one thread and module tests in a pool of workers beside it, and answers the results in the order of the paths.
(define (run-tests-parallel paths)
  (define slots (make-vector (length paths) #f))
  (define idx (for/list ([p (in-list paths)] [i (in-naturals)]) (cons i p)))
  (define (module? p) (pair? (line-values (test-lines p) "module")))
  (define keys (filter (lambda (ip) (not (module? (cdr ip)))) idx))
  (define mods (filter (lambda (ip) (module? (cdr ip))) idx))
  (define (do! ip)
    (define nm (path->string (cdr ip)))
    (live (string-append "test " nm " start"))
    (define r (with-handlers ([void (lambda (e) (list nm 0.0 #f (list (string-append "    the test crashed: " (if (exn? e) (exn-message e) "unknown")))))])
                (let ([tf (build-path (find-system-path (quote home-dir)) (format ".aiu-trace-~a.log" (car ip)))]) (with-handlers ([void void]) (delete-file tf)) (parameterize ([current-trace-file tf]) (run-test (cdr ip))))))
    (live (string-append "test " (if (pair? r) (car r) nm) " done"))
    (vector-set! slots (car ip) r))
  (define lock (make-semaphore 1))
  (define todo (append keys mods))
  (define (next!) (call-with-semaphore lock (lambda () (if (null? todo) #f (let ([x (car todo)]) (set! todo (cdr todo)) x)))))
  (define workers (max 1 (let ([e (getenv "AIU_JOBS")]) (or (and e (string->number e)) (* 2 (cores))))))
  (void)
  (define pool (for/list ([w (in-range workers)]) (thread (lambda () (let loop () (define ip (next!)) (when ip (do! ip) (loop)))))))
  (for-each thread-wait pool)
  (vector->list slots))
