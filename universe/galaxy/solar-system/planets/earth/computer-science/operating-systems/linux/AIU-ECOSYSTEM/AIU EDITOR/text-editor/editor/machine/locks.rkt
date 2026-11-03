#lang racket/base

(require racket/file
         racket/path
         "cancel.rkt"
         "../errors/raise.rkt")

(struct lock (path signal token) #:transparent)

(define (lock-path-for target)
  (build-path (path->complete-path target) ".lock"))

(define (acquire-lock target)
  (define p (lock-path-for target))
  (cond
    [(directory-exists? p) #f]
    [else
     (with-handlers ([exn:fail? (lambda (e) #f)])
       (make-directory p)
       (lock p (make-semaphore) (new-cancel-token)))]))

(define (release-lock l)
  (when (directory-exists? (lock-path l))
    (with-handlers ([exn:fail? (lambda (e) (void))])
      (delete-directory (lock-path l))))
  (semaphore-post (lock-signal l)))

(define (with-lock target body)
  (define l (acquire-lock target))
  (if (not l)
      (error-of 'err-lock-busy "the editor" (path->string (lock-path-for target))
                "another writer holds the lock"
                "wait for the release event and try again")
      (dynamic-wind
        (lambda () (void))
        body
        (lambda () (release-lock l)))))

(define (with-lock-wait target body)
  (define l (acquire-lock target))
  (cond
    [(not l)
     (wait-for-foreign-release (lock-path-for target))
     (with-lock-wait target body)]
    [else
     (dynamic-wind
       (lambda () (void))
       body
       (lambda () (release-lock l)))]))

(define (wait-for-foreign-release lock-path)
  (if (directory-exists? lock-path)
      (error-of 'err-lock-busy "the editor" (path->string lock-path)
                "another writer holds the lock and no release event is wired yet"
                "retry when the file-change event says the lock is gone")
      (void)))
