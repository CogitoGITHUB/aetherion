#lang racket/base
;; shadow.rkt: undo commits. After an autosave the saved file is committed on the branch
;; aiu-undo of the git repository that holds it, one commit for each burst of edits.
;; The branch is never checked out: each commit is built with git plumbing and a private
;; temporary index file, so the real index, HEAD and work tree are never touched.
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

;; zero-id is the old value that update-ref needs when the branch does not exist yet.
(define zero-id "0000000000000000000000000000000000000000")

;; log-error! writes a problem to a file, because nothing may be printed over the page.
(define (log-error! text)
  (with-handlers ([void void])
    (call-with-output-file (build-path (find-system-path (quote home-dir)) ".aiu-undo-error.txt")
      (lambda (out) (write-string text out) (newline out))
      #:exists (quote truncate))))

;; slurp reads a port to the end and answers the text.
(define (slurp in)
  (let ([out (open-output-string)])
    (let loop ()
      (let ([s (read-string 4096 in)])
        (unless (eof-object? s) (write-string s out) (loop))))
    (get-output-string out)))

;; chomp removes the line end from the end of a text.
(define (chomp s)
  (regexp-replace #rx"[\r\n]+$" s ""))

;; git-run runs git in a folder, with an optional private index file, and answers
;; a list of exit status, output text and error text.
(define (git-run dir index . args)
  (let ([env (environment-variables-copy (current-environment-variables))])
    (when index
      (environment-variables-set! env #"GIT_INDEX_FILE" (string->bytes/utf-8 index)))
    (parameterize ([current-directory dir] [current-environment-variables env])
      (let-values ([(sp out in err)
                    (apply subprocess #f #f #f git-exe
                           "-c" "commit.gpgsign=false" "-c" "user.name=aiu-undo"
                           "-c" "user.email=aiu-undo@localhost" args)])
        (close-output-port in)
        (let* ([o (slurp out)] [e (slurp err)])
          (close-input-port out)
          (close-input-port err)
          (subprocess-wait sp)
          (list (subprocess-status sp) o e))))))

;; git-try answers the output of a git call without its line end, or false when it failed.
(define (git-try dir index . args)
  (let ([r (apply git-run dir index args)])
    (and (zero? (car r)) (chomp (cadr r)))))

;; git-need answers the output of a git call, or raises an error that holds git messages.
(define (git-need dir index . args)
  (let ([r (apply git-run dir index args)])
    (if (zero? (car r))
        (chomp (cadr r))
        (error (string-append "git " (car args) ": " (caddr r))))))

;; stat->words turns a git shortstat line into the change text of the message.
(define (stat->words stat)
  (let ([ins (regexp-match #px"(\\d+) insertion" stat)]
        [del (regexp-match #px"(\\d+) deletion" stat)])
    (string-append "+" (if ins (cadr ins) "0") " -" (if del (cadr del) "0") " lines")))

;; build-commit! adds the file to the tree of the branch aiu-undo and commits it when it changed.
(define (build-commit! top gitdir full rel name)
  (let ([index (path->string
                (build-path gitdir (string-append "aiu-undo-index-"
                                                  (number->string (current-milliseconds)))))]
        [parent (git-try top #f "rev-parse" "--verify" "-q" "refs/heads/aiu-undo^{commit}")])
    (dynamic-wind
     void
     (lambda ()
       (when parent (git-need top index "read-tree" parent))
       (let ([blob (git-need top #f "hash-object" "-w" "--no-filters" "--" full)])
         (git-need top index "update-index" "--add" "--cacheinfo" "100644" blob rel)
         (let* ([tree (git-need top index "write-tree")]
                [old-tree (if parent
                              (git-need top #f "rev-parse" (string-append parent "^{tree}"))
                              (git-need top #f "hash-object" "-t" "tree" "/dev/null"))])
           (unless (equal? tree old-tree)
             (let* ([stat (git-need top #f "diff" "--shortstat" old-tree tree "--" rel)]
                    [msg (string-append name ": " (stat->words stat))]
                    [new (apply git-need top #f "commit-tree" tree "-m" msg
                                (if parent (list "-p" parent) (list)))])
               (git-need top #f "update-ref" "-m" "aiu-undo" "refs/heads/aiu-undo"
                         new (or parent zero-id)))))))
     (lambda () (with-handlers ([void void]) (delete-file index))))))

;; commit-file! finds the repository of the file and commits it, or does nothing outside a repository.
(define (commit-file! full)
  (when (and (file-exists? full) (regexp-match? #rx"^/" full))
    (let-values ([(base name dir?) (split-path full)])
      (let ([where (git-try base #f "rev-parse" "--absolute-git-dir" "--show-toplevel" "--show-prefix")])
        (when where
          (let* ([m (regexp-match #rx"^([^\n]*)\n([^\n]*)\n?([^\n]*)" where)]
                 [gitdir (cadr m)]
                 [top (caddr m)]
                 [prefix (cadddr m)]
                 [name-str (path->string name)]
                 [head (git-try top #f "symbolic-ref" "-q" "HEAD")])
            (if (equal? head "refs/heads/aiu-undo")
                (log-error! "HEAD is on aiu-undo, no undo commit was made")
                (build-commit! top gitdir full (string-append prefix name-str) name-str))))))))

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
