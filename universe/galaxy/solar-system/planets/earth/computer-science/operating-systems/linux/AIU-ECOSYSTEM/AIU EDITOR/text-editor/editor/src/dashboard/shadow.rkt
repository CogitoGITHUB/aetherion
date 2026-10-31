#lang racket/base
;; shadow.rkt: undo commits. When a file is saved (space s, tab s, escape in the write layer) it is
;; committed on the branch aiu-undo of the git repository that holds it. The branch is never checked
;; out: the commit is built with git plumbing and a private temporary index file, so the real index,
;; HEAD and work tree are never touched. Each file has a current node, kept in the git folder; a save
;; commits on top of that node, so a save after an undo makes a branch, and a tip that would be lost
;; is kept under refs/aiu-undo-old. The editor starts ONE niced sh process for each commit.
;; Needs only racket/base and runs in threads.

;; shadow-note! tells the worker that a file was saved; shadow-commit-now! commits at once and waits;
;; shadow-key answers the name part of the current-node file of a path.
(provide shadow-note! shadow-commit-now! shadow-key)

;; quiet-ms is how long the files must stay unchanged before a commit is made.
(define quiet-ms 500)

;; lock guards the state below.
(define lock (make-semaphore 1))

;; pending holds the complete paths waiting for a commit, used as a set.
(define pending (make-hash))

;; last-note holds the time of the latest note in milliseconds.
(define last-note 0)

;; worker is the running worker thread, or false.
(define worker #f)

;; sh-exe is the shell program, or false.
(define sh-exe (find-executable-path "sh"))

;; nice-exe is the program that lowers the priority of a command, or false.
(define nice-exe (find-executable-path "nice"))

;; shadow-key turns a complete path into a name that is safe in a file name.
(define (shadow-key full)
  (regexp-replace* #rx"[^A-Za-z0-9]" full "_"))

;; commit-script is the shell program of one undo commit; it gets the saved file and its key as arguments.
(define commit-script #<<END
fail() { echo "$1" >&2; }
g() { git -c commit.gpgsign=false -c user.name=aiu-undo -c user.email=aiu-undo@localhost "$@"; }
f="$1"
cd "$(dirname "$f")" || exit 0
info=$(git rev-parse --absolute-git-dir --show-toplevel --show-prefix --symbolic-full-name HEAD 2>/dev/null) || exit 0
gitdir=$(printf "%s\n" "$info" | sed -n 1p)
top=$(printf "%s\n" "$info" | sed -n 2p)
prefix=$(printf "%s\n" "$info" | sed -n 3p)
head=$(printf "%s\n" "$info" | sed -n 4p)
if [ "$head" = "refs/heads/aiu-undo" ]; then fail "HEAD is on aiu-undo, no undo commit was made"; exit 0; fi
cd "$top" || exit 0
rel="$prefix$(basename "$f")"
idx="$gitdir/aiu-undo-index-$$"
curf="$gitdir/aiu-undo-cur-$2"
gi() { GIT_INDEX_FILE="$idx" git -c commit.gpgsign=false -c user.name=aiu-undo -c user.email=aiu-undo@localhost "$@"; }
work() {
  tip=$(git rev-parse --verify -q "refs/heads/aiu-undo^{commit}")
  cur=""
  if [ -f "$curf" ]; then cur=$(cat "$curf"); fi
  parent="$tip"
  if [ -n "$cur" ] && git cat-file -e "$cur^{commit}" 2>/dev/null; then parent="$cur"; fi
  if [ -n "$parent" ]; then gi read-tree "$parent" || { fail "read-tree failed"; return; }; fi
  blob=$(git hash-object -w --no-filters -- "$f") || { fail "hash-object failed"; return; }
  gi update-index --add --cacheinfo 100644 "$blob" "$rel" || { fail "update-index failed"; return; }
  tree=$(gi write-tree) || { fail "write-tree failed"; return; }
  if [ -n "$parent" ]; then old=$(git rev-parse "$parent^{tree}"); else old=$(git hash-object -t tree /dev/null); fi
  if [ "$tree" = "$old" ]; then
    if [ -n "$parent" ]; then printf "%s\n" "$parent" > "$curf"; fi
    return
  fi
  stat=$(git diff --no-ext-diff --shortstat "$old" "$tree" -- "$rel")
  ins=$(printf "%s" "$stat" | sed -n "s/.* \([0-9][0-9]*\) insertion.*/\1/p")
  del=$(printf "%s" "$stat" | sed -n "s/.* \([0-9][0-9]*\) deletion.*/\1/p")
  msg="$(basename "$f"): +${ins:-0} -${del:-0} lines"
  if [ -n "$parent" ]; then new=$(g commit-tree "$tree" -p "$parent" -m "$msg"); else new=$(g commit-tree "$tree" -m "$msg"); fi
  if [ -z "$new" ]; then fail "commit-tree failed"; return; fi
  if [ -n "$tip" ] && ! git merge-base --is-ancestor "$tip" "$new" 2>/dev/null; then
    git update-ref "refs/aiu-undo-old/$tip" "$tip" || fail "old tip ref failed"
  fi
  g update-ref -m aiu-undo refs/heads/aiu-undo "$new" "${tip:-0000000000000000000000000000000000000000}" || { fail "update-ref failed"; return; }
  printf "%s\n" "$new" > "$curf"
}
work
rm -f "$idx"
END
  )

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

;; commit-file! runs the commit script for one file and logs whatever it says on stderr.
(define (commit-file! full)
  (when (and sh-exe (file-exists? full) (regexp-match? #rx"^/" full))
    (let-values ([(sp out in err)
                  (if nice-exe
                      (subprocess #f #f #f nice-exe "-n" "19" sh-exe "-c" commit-script "aiu-undo" full (shadow-key full))
                      (subprocess #f #f #f sh-exe "-c" commit-script "aiu-undo" full (shadow-key full)))])
      (close-output-port in)
      (let* ([o (slurp out)] [e (slurp err)])
        (close-input-port out)
        (close-input-port err)
        (subprocess-wait sp)
        (when (regexp-match? #rx"[^ \r\n]" e) (log-error! e))))))

;; commit-safe! commits one file and turns any error into a line in the error file.
(define (commit-safe! full)
  (with-handlers ([(lambda (e) #t)
                   (lambda (e) (log-error! (if (exn? e) (exn-message e) "unknown error")))])
    (commit-file! full)))

;; run-worker waits until the notes stop for quiet-ms, commits them, and ends when idle.
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

;; shadow-note! is called after a save, with the saved file; AIU_NO_UNDO switches it off.
(define (shadow-note! file)
  (when (and sh-exe (not (getenv "AIU_NO_UNDO")) (or (string? file) (path? file)))
    (let ([full (path->string (path->complete-path file))])
      (call-with-semaphore
       lock
       (lambda ()
         (hash-set! pending full #t)
         (set! last-note (current-inexact-milliseconds))
         (unless worker (set! worker (thread run-worker))))))))

;; shadow-commit-now! commits a saved file at once and waits for the commit; the undo mode uses it.
(define (shadow-commit-now! file)
  (when (and sh-exe (not (getenv "AIU_NO_UNDO")) (or (string? file) (path? file)))
    (commit-safe! (path->string (path->complete-path file)))))
