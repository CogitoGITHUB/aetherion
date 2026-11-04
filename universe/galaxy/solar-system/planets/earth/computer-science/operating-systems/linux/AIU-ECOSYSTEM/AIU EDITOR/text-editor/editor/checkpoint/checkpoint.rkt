#lang racket/base

(require racket/file
         racket/path
         racket/list
         racket/path
         racket/port
         racket/string
         racket/system
         "../machine/directories-shared.rkt")

(define checkpoints-dir
  (build-path (state-dir) "checkpoints"))

(define (tracked-files root)
  (define output (run-git root "ls-files"))
  (filter (lambda (line) (not (string=? line "")))
          (string-split output "\n")))

(define (untracked-files root)
  (define output (run-git root "ls-files" "--others" "--exclude-standard"))
  (filter (lambda (line) (not (string=? line "")))
          (string-split output "\n")))

(define git "/usr/bin/git")

(define shell "/bin/sh")

(define (run-git root . arguments)
  (define out-file (build-path (state-dir) "git-out"))
  (define status-file (build-path (state-dir) "git-status"))
  (ensure-dir (state-dir))
  (define quoted
    (string-join
     (for/list ([a (in-list arguments)])
       (string-append "'" (if (path? a) (path->string a) a) "'"))
     " "))
  (define root-text (if (path? root) (path->string root) root))
  (system* shell
           "-c"
           (string-append git " -C '" root-text "' " quoted
                          " > '" (path->string out-file) "' 2>/dev/null; echo -n $? > '"
                          (path->string status-file) "'"))
  (if (file-exists? out-file) (file->string out-file) ""))

(define (git-ok? root . arguments)
  (apply run-git root arguments)
  (define status-file (build-path (state-dir) "git-status"))
  (and (file-exists? status-file)
       (string=? (string-trim (file->string status-file)) "0")))

(define (tree-root file)
  (define directory
    (simplify-path
     (path->complete-path
      (if (directory-exists? file) file (build-path file 'up)))))
  (define answer (string-trim (run-git directory "rev-parse" "--show-toplevel")))
  (if (string=? answer "") directory answer))

(define (checkpoint root why)
  (if (string=? (string-trim why) "")
      #f
      (let* ([files (tracked-files root)]
             [loose (untracked-files root)]
             [note (format "the checkpoint before an agent acted: ~a~a"
                           why
                           (if (null? loose)
                               ""
                               (format "~nnot tracked, so not in this commit: ~a"
                                       (string-join loose " "))))])
        (for ([file (in-list files)])
          (run-git root "add" "--" file))
        (define note-file (build-path (state-dir) "git-note"))
        (call-with-output-file note-file
          (lambda (port) (display note port))
          #:exists 'truncate)
        (define made (run-git root "commit" "-F" note-file "--allow-empty"))
        (if (string=? made "")
            #f
            (let ([name (string-trim (run-git root "rev-parse" "--short" "HEAD"))])
              (remember-checkpoint name)
              name)))))

(define checkpoints-file
  (build-path checkpoints-dir "checkpoints"))

(define (checkpoints)
  (if (file-exists? checkpoints-file)
      (filter (lambda (line) (not (string=? line "")))
              (string-split (file->string checkpoints-file) "\n"))
      '()))

(define (remember-checkpoint name)
  (ensure-dir checkpoints-dir)
  (call-with-output-file checkpoints-file
    (lambda (port)
      (for ([other (in-list (checkpoints))])
        (display other port)
        (newline port))
      (display name port)
      (newline port))
    #:exists 'truncate)
  name)

(provide checkpoints-dir
         tree-root
         git-ok?
         checkpoints-file
         tracked-files
         untracked-files
         run-git
         checkpoint
         checkpoints
         remember-checkpoint)
