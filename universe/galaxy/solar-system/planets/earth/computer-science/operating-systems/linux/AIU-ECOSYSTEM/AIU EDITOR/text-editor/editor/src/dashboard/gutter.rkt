#lang racket/base
;; gutter.rkt: the git hunks of the open file, kept for the left strip of the
;; page. Git runs in a thread, four seconds after the first ask, so the first
;; paint and the first keys never wait for it. Only racket/base is loaded.

;; kept holds the hunks of the file in kept-file: lists of first line, last
;; line and mark.
(define kept (box null))

;; kept-file holds the file the kept hunks belong to.
(define kept-file (box #f))

;; busy holds whether a thread is asking git now.
(define busy (box #f))

;; stamp holds the second git was last asked about a file.
(define stamp (box 0))

;; gutter-hunks answers the hunks kept for a file, or none for another file.
(define (gutter-hunks file)
  (if (equal? (unbox kept-file) file) (unbox kept) null))

;; git-diff answers what git diff prints for one file with no context lines.
(define (git-diff file)
  (define git (find-executable-path "git"))
  (define-values (base name dir?) (split-path (path->complete-path file)))
  (if (and git (path? base) (path? name))
      (let-values ([(sp out in err) (subprocess #f #f #f git "-C" (path->string base) "diff" "-U0" "--no-color" "--" (path->string name))])
        (close-output-port in)
        (let ([s (read-string 200000 out)])
          (close-input-port out)
          (close-input-port err)
          (subprocess-wait sp)
          (if (string? s) s "")))
      ""))

;; parse-hunks answers the hunks of a diff text as lists of first line, last
;; line and mark: plus for added lines, equals for changed, minus for removed.
(define (parse-hunks text)
  (for/list ([m (in-list (regexp-match* #px"(?m:^@@ -[0-9]+(?:,([0-9]+))? \\+([0-9]+)(?:,([0-9]+))? @@)" text #:match-select values))])
    (define old (if (cadr m) (string->number (cadr m)) 1))
    (define at (string->number (caddr m)))
    (define new (if (cadddr m) (string->number (cadddr m)) 1))
    (cond [(= new 0) (list at at "-")]
          [(= old 0) (list at (+ at new -1) "+")]
          [else (list at (+ at new -1) "=")])))

;; gutter-refresh-maybe asks git in a thread when the answer is fifteen
;; seconds old or belongs to another file, and calls again when it changed.
(define (gutter-refresh-maybe file again)
  (when (and (not (unbox busy))
             (or (not (equal? (unbox kept-file) file))
                 (>= (- (current-seconds) (unbox stamp)) 15)))
    (define first? (zero? (unbox stamp)))
    (set-box! busy #t)
    (set-box! stamp (current-seconds))
    (thread
     (lambda ()
       (when first? (sleep 4))
       (define hunks (with-handlers ([(lambda (e) #t) (lambda (e) null)]) (parse-hunks (git-diff file))))
       (define changed? (not (and (equal? (unbox kept-file) file) (equal? hunks (unbox kept)))))
       (set-box! kept hunks)
       (set-box! kept-file file)
       (set-box! busy #f)
       (when changed? (again))))))

;; gutter-stale! makes the strip ask git again at the next paint.
(define (gutter-stale!) (set-box! stamp 1))

(provide gutter-stale! gutter-hunks gutter-refresh-maybe)
