#lang racket/base

(require racket/file
         racket/string
         racket/system
         "directories.rkt")

(define shell "/bin/sh")

(define (run-program command seconds)
  (define out-file (build-path (state-dir) "run-out"))
  (define err-file (build-path (state-dir) "run-err"))
  (define code-file (build-path (state-dir) "run-code"))
  (ensure-dir (state-dir))
  (for ([file (in-list (list out-file err-file code-file))])
    (when (file-exists? file) (delete-file file)))
  (define broke? #f)
  (with-handlers ([exn:break? (lambda (why) (set! broke? #t))])
    (system* shell "-c"
             (string-append (format "timeout ~a " seconds) command
                            " < /dev/null > '" (path->string out-file) "' 2> '" (path->string err-file)
                            "'; echo -n $? > '" (path->string code-file) "'")))
  (hash 'out (read-text out-file)
        'err (read-text err-file)
        'code (read-code code-file)
        'broke broke?))

(define (read-text path)
  (if (file-exists? path) (file->string path) ""))

(define (read-code path)
  (if (file-exists? path)
      (or (string->number (string-trim (file->string path))) -1)
      -1))

(define (shell-quote text)
  (string-append "'" (string-replace text "'" "'\\''") "'"))

(provide run-program
         shell-quote)
