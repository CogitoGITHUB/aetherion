#lang racket/base

(require racket/file
         racket/port
         racket/string
         racket/system
         "../editor/join/transport.rkt"
         "../editor/join/protocol.rkt"
         "../editor/machine/directories.rkt")

(define the-name "AIU editor gate")

(define the-mail "gate@localhost")

(define (make-repository)
  (define directory (make-temporary-directory "aiu-git-check-~a"))
  (define file (build-path directory "notes.txt"))
  (call-with-output-file file #:exists 'truncate
    (lambda (out) (display "the first line\n" out)))
  (parameterize ([current-directory directory])
    (git "init" "-b" "main")
    (git "add" "notes.txt")
    (git "-c" (format "user.name=~a" the-name)
         "-c" (format "user.email=~a" the-mail)
         "commit" "-m" "the first commit"))
  (values directory file))

(define (git . args)
  (define out (open-output-string))
  (define err (open-output-string))
  (define code
    (parameterize ([current-output-port out]
                   [current-error-port err])
      (apply system*/exit-code (git-bin) args)))
  (unless (and (integer? code) (zero? code))
    (error 'git-check
           (format "the git command ~a failed: ~a" (string-join args " ") (get-output-string err))))
  (get-output-string out))

(define (ask op file)
  (define answer
    (call-over-wire (hot-path-bin) '()
                    (hasheq 'op op 'args (hasheq 'file (path->string file)))))
  (response-data answer))

(define (the-value data name)
  (define found (hash-ref data name ""))
  (if (string? found) found (format "~a" found)))

(define (status-of directory)
  (parameterize ([current-directory directory])
    (string-trim (git "status" "--porcelain"))))

(define (main)
  (define faults '())
  (define-values (directory file) (make-repository))
  (define clean (ask "git" file))
  (unless (string=? (the-value clean 'git-branch) "main")
    (set! faults (cons (format "the branch is ~a, and it should be main"
                                (the-value clean 'git-branch)) faults)))
  (unless (string=? (the-value clean 'git-file-working) "clean")
    (set! faults (cons (format "a committed file is ~a in the working tree, and it should be clean"
                                (the-value clean 'git-file-working)) faults)))
  (unless (string=? (the-value clean 'git-unstaged) "0")
    (set! faults (cons (format "the repository holds ~a unstaged changes, and it should hold none"
                                (the-value clean 'git-unstaged)) faults)))
  (call-with-output-file file #:exists 'truncate
    (lambda (out) (display "the first line\nthe second line\n" out)))
  (define before (status-of directory))
  (define changed (ask "git" file))
  (unless (string=? (the-value changed 'git-file-working) "modified")
    (set! faults (cons (format "a changed file is ~a in the working tree, and it should be modified"
                                (the-value changed 'git-file-working)) faults)))
  (unless (string=? (the-value changed 'git-file-index) "unchanged")
    (set! faults (cons (format "the index says ~a of the file, and it should say unchanged"
                                (the-value changed 'git-file-index)) faults)))
  (unless (string=? (the-value changed 'git-unstaged) "1")
    (set! faults (cons (format "the repository holds ~a unstaged changes, and it should hold one"
                                (the-value changed 'git-unstaged)) faults)))
  (define difference (ask "git-diff" file))
  (unless (string=? (the-value difference 'git-diff-comparison) "working tree against index")
    (set! faults (cons (format "the comparison is ~a, and it should be the working tree against the index"
                                (the-value difference 'git-diff-comparison)) faults)))
  (unless (string=? (the-value difference 'git-diff-hunks) "1")
    (set! faults (cons (format "the diff holds ~a hunks, and it should hold one"
                                (the-value difference 'git-diff-hunks)) faults)))
  (define outside (build-path (make-temporary-directory "aiu-git-outside-~a") "nothing.txt"))
  (define refused (ask "git" outside))
  (unless (string=? (the-value refused 'git-state) "unknown")
    (set! faults (cons (format "a file outside a repository is ~a, and it should be refused"
                                (the-value refused 'git-state)) faults)))
  (when (string=? (the-value refused 'git-file-working) "clean")
    (set! faults (cons "a file outside a repository was reported as clean" faults)))
  (unless (string=? before (status-of directory))
    (set! faults (cons "the inspection changed the repository" faults)))
  (if (null? faults)
      (begin
        (printf "OK git-check — the facts, the diff and the refusal hold, and the repository is untouched\n")
        (exit 0))
      (begin
        (for ([fault (in-list (reverse faults))])
          (printf "FAIL git-check — ~a\n" fault))
        (exit 1))))

(module+ main
  (main))
