#lang racket/base
(require "../errors/err.rkt"
         "../errors/raise.rkt"
         "../narration/wait-door.rkt"
         "directories.rkt")

(provide (struct-out lock)
         acquire-lock!
         release-lock!
         lock-root)

(struct lock (path who why) #:transparent)

(define (lock-root)
  (build-path (xdg-state-home) "multiplexer" "locks"))

(define (lock-slot name)
  (build-path (lock-root) name))

(define (owner-path path)
  (build-path path "owner"))

(define (write-text path text)
  (define out (open-output-file path #:exists 'replace))
  (write-string text out)
  (close-output-port out))

(define (read-text path)
  (with-handlers ([exn:fail? (lambda (e) #f)])
    (define in (open-input-file path))
    (define text
      (let loop ([chars '()])
        (define c (read-char in))
        (if (eof-object? c)
            (list->string (reverse chars))
            (loop (cons c chars)))))
    (close-input-port in)
    text))

(define (parent-dir path)
  (define s (if (path? path) (path->string path) path))
  (define cut
    (let loop ([i (sub1 (string-length s))])
      (cond
        [(< i 0) 0]
        [(char=? (string-ref s i) #\/) i]
        [else (loop (sub1 i))])))
  (if (zero? cut) "/" (substring s 0 cut)))

(define (ensure-dir path)
  (unless (directory-exists? path)
    (define s (if (path? path) (path->string path) path))
    (define parent (parent-dir s))
    (unless (equal? parent s)
      (ensure-dir parent))
    (with-handlers ([exn:fail:filesystem? (lambda (e) (void))])
      (make-directory path))))

(define (take path)
  (with-handlers ([exn:fail:filesystem? (lambda (e) #f)])
    (make-directory path)
    #t))

(define (starts-with? s prefix)
  (and (>= (string-length s) (string-length prefix))
       (string=? (substring s 0 (string-length prefix)) prefix)))

(define (holder-note path)
  (define text (read-text (owner-path path)))
  (if (string? text) text "no owner record (a lock from a writer that has died)"))

(define (retry path left pause-ms)
  (cond
    [(<= left 0) #f]
    [else
     (sleep (/ pause-ms 1000.0))
     (if (take path) #t (retry path (sub1 left) pause-ms))]))

(define (acquire-lock! run name #:who who #:why why
                       #:tries [tries 50]
                       #:pause-ms [pause-ms 200])
  (when (blank-string? who)
    (raise-error "the lock holder was not named"
                 "machine/locks acquire-lock!"
                 name
                 "a lock must say who holds it, so the next writer can ask"
                 #:rule 'locks/who-required))
  (when (blank-string? why)
    (raise-error "the lock reason was blank"
                 "machine/locks acquire-lock!"
                 name
                 "a lock must say why it is held, so waiting is readable"
                 #:rule 'locks/why-required))
  (define path (lock-slot name))
  (ensure-dir (lock-root))
  (define got-now (take path))
  (define token
    (if got-now
        #f
        (wait-for run name
                  #:why (format "~a is held by another writer; ~a; waiting and retrying"
                                name why)
                  #:how "the one-writer lock directory")))
  (define got (if got-now #t (retry path tries pause-ms)))
  (when token
    (wait-done token #:result (if got "the lock was released to me" "no lock after the last try")))
  (if got
      (begin
        (write-text (owner-path path) (format "~a\n~a\n~a\n" who why (current-seconds)))
        (lock path who why))
      (raise-error "the lock stayed held by another writer"
                   "machine/locks acquire-lock!"
                   (path->string path)
                   (format "~a; waited ~a tries and forced nothing" why tries)
                   #:rule 'locks/never-force
                   #:detail (holder-note path))))

(define (release-lock! l)
  (define path (lock-path l))
  (cond
    [(not (directory-exists? path)) (void)]
    [else
     (define note (read-text (owner-path path)))
     (define mine (and (string? note)
                       (starts-with? note (format "~a\n" (lock-who l)))))
     (unless mine
       (raise-error "the lock is not mine to release"
                    "machine/locks release-lock!"
                    (path->string path)
                    "the owner record names another writer, or is missing; removing it breaks one"
                    #:rule 'locks/never-force))
     (when (file-exists? (owner-path path))
       (delete-file (owner-path path)))
     (delete-directory path)]))
