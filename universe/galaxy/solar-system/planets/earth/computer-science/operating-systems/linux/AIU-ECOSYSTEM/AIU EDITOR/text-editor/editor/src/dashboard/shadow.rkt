#lang racket/base
;; shadow.rkt: undo commits. After an autosave the saved file is committed to a private
;; repository outside the project (~/.aiu-undo/repo.git), one commit for each burst of edits.
;; Needs only racket/base and runs in threads, never on the key path.

;; shadow-note! is the one entry point: it tells the worker that a file was saved.
(provide shadow-note!)

;; quiet-ms is how long the files must stay unchanged before a commit is made.
(define quiet-ms 1000)

;; lock guards the state below.
(define lock (make-semaphore 1))

;; pending holds the complete paths waiting for a commit, used as a set.
(define pending (make-hash))

;; last-note holds the time of the latest note in milliseconds.
(define last-note 0)

;; worker is the running worker thread, or false.
(define worker #f)

;; git-exe is the git program, or false when it is not installed.
(define git-exe (find-executable-path "git"))

;; undo-dir answers the folder that holds the private repository.
(define (undo-dir)
  (build-path (find-system-path (quote home-dir)) ".aiu-undo"))

;; repo-dir answers the git directory of the private repository.
(define (repo-dir)
  (build-path (undo-dir) "repo.git"))

;; log-error! writes a problem to a file, because nothing may be printed over the page.
(define (log-error! text)
  (with-handlers ([void void])
    (unless (directory-exists? (undo-dir)) (make-directory (undo-dir)))
    (call-with-output-file (build-path (undo-dir) "last-error.txt")
      (lambda (out) (write-string text out) (newline out))
      #:exists (quote truncate))))

;; slurp reads a port to the end and answers the text.
(define (slurp in)
  (let ([out (open-output-string)])
    (let loop ()
      (let ([s (read-string 4096 in)])
        (unless (eof-object? s) (write-string s out) (loop))))
    (get-output-string out)))

;; git-run runs git and answers a list of exit status, output text and error text.
(define (git-run . args)
  (parameterize ([current-directory "/"])
    (let-values ([(sp out in err) (apply subprocess #f #f #f git-exe args)])
      (close-output-port in)
      (let* ([o (slurp out)] [e (slurp err)])
        (close-input-port out)
        (close-input-port err)
        (subprocess-wait sp)
        (list (subprocess-status sp) o e)))))

;; shadow-git runs git against the private repository only, never the project one.
(define (shadow-git . args)
  (apply git-run "-c" "commit.gpgsign=false" "--git-dir" (path->string (repo-dir))
         "--work-tree" "/" args))

;; ensure-repo! creates the private repository on first use and sets its own user.
(define (ensure-repo!)
  (unless (file-exists? (build-path (repo-dir) "HEAD"))
    (unless (directory-exists? (undo-dir)) (make-directory (undo-dir)))
    (git-run "init" "--bare" "-q" (path->string (repo-dir)))
    (for-each (lambda (kv) (shadow-git "config" (car kv) (cdr kv)))
              (list (cons "core.bare" "false")
                    (cons "user.name" "aiu-undo")
                    (cons "user.email" "aiu-undo@localhost")
                    (cons "status.showUntrackedFiles" "no")))))

;; stat->words turns a git shortstat line into the change text of the message.
(define (stat->words stat)
  (let ([ins (regexp-match #px"(\\d+) insertion" stat)]
        [del (regexp-match #px"(\\d+) deletion" stat)])
    (string-append "+" (if ins (cadr ins) "0") " -" (if del (cadr del) "0") " lines")))

;; commit-file! stores the file in the private index and commits it when it changed.
(define (commit-file! full)
  (ensure-repo!)
  (when (and (file-exists? full) (regexp-match? #rx"^/" full))
    (let ([h (shadow-git "hash-object" "-w" "--no-filters" "--" full)])
      (if (not (zero? (car h)))
          (log-error! (string-append "hash-object: " (caddr h)))
          (let* ([blob (regexp-replace* #rx"[ \r\n]+" (cadr h) "")]
                 [u (shadow-git "update-index" "--add" "--cacheinfo"
                                (string-append "100644," blob "," (substring full 1)))])
            (if (not (zero? (car u)))
                (log-error! (string-append "update-index: " (caddr u)))
                (let ([d (shadow-git "diff" "--cached" "--shortstat")])
                  (when (regexp-match? #rx"[^ \r\n]" (cadr d))
                    (let-values ([(base name dir?) (split-path full)])
                      (let ([c (shadow-git "commit" "-q" "--no-verify" "-m"
                                           (string-append (path->string name) ": "
                                                          (stat->words (cadr d))))])
                        (unless (zero? (car c))
                          (log-error! (string-append "commit: " (caddr c)))))))))))))) 

;; commit-safe! commits one file and turns any error into a line in the error file.
(define (commit-safe! full)
  (with-handlers ([(lambda (e) #t)
                   (lambda (e) (log-error! (if (exn? e) (exn-message e) "unknown error")))])
    (commit-file! full)))

;; run-worker waits until the edits stop for quiet-ms, commits them, and ends when idle.
(define (run-worker)
  (let loop ()
    (sleep 0.25)
    (let ([due (call-with-semaphore
                lock
                (lambda ()
                  (if (>= (- (current-inexact-milliseconds) last-note) quiet-ms)
                      (let ([files (hash-keys pending)])
                        (hash-clear! pending)
                        (when (null? files) (set! worker #f))
                        files)
                      (quote wait))))])
      (cond [(eq? due (quote wait)) (loop)]
            [(null? due) (void)]
            [else (for-each commit-safe! due) (loop)]))))

;; shadow-note! is called after every autosave with the saved file.
(define (shadow-note! file)
  (when (and git-exe (or (string? file) (path? file)))
    (let ([full (path->string (path->complete-path file))])
      (call-with-semaphore
       lock
       (lambda ()
         (hash-set! pending full #t)
         (set! last-note (current-inexact-milliseconds))
         (unless worker (set! worker (thread run-worker))))))))
