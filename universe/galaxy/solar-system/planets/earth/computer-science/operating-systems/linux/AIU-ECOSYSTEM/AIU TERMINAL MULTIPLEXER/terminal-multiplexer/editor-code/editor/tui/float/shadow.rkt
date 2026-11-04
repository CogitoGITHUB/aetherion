#lang racket/base

(provide shadow-note! shadow-commit-now! shadow-key)

(define quiet-ms 500)

(define lock (make-semaphore 1))

(define pending (make-hash))

(define last-note 0)

(define worker #f)

(define sh-exe (find-executable-path "sh"))

(define nice-exe (find-executable-path "nice"))

(define (shadow-key full)
  (regexp-replace* #rx"[^A-Za-z0-9]" full "_"))

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

(define (log-error! text)
  (with-handlers ([void void])
    (call-with-output-file (build-path (find-system-path (quote home-dir)) ".aiu-undo-error.txt")
      (lambda (out) (write-string text out) (newline out))
      #:exists (quote truncate))))

(define (slurp in)
  (let ([out (open-output-string)])
    (let loop ()
      (let ([s (read-string 4096 in)])
        (unless (eof-object? s) (write-string s out) (loop))))
    (get-output-string out)))

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

(define commit-lock (make-semaphore 1))

(define (commit-safe! full)
  (with-handlers ([(lambda (e) #t)
                   (lambda (e) (log-error! (if (exn? e) (exn-message e) "unknown error")))])
    (call-with-semaphore commit-lock (lambda () (commit-file! full)))))

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

(define (shadow-note! file)
  (when (and sh-exe (not (getenv "AIU_NO_UNDO")) (or (string? file) (path? file)))
    (let ([full (path->string (path->complete-path file))])
      (call-with-semaphore
       lock
       (lambda ()
         (hash-set! pending full #t)
         (set! last-note (current-inexact-milliseconds))
         (unless worker (set! worker (thread run-worker))))))))

(define (shadow-commit-now! file)
  (when (and sh-exe (not (getenv "AIU_NO_UNDO")) (or (string? file) (path? file)))
    (commit-safe! (path->string (path->complete-path file)))))
