#lang racket/base

(require (only-in "../float/box.rkt" paint-ready))

(define kept (box null))

(define kept-file (box #f))

(define busy (box #f))

(define stamp (box 0))

(define (gutter-hunks file)
  (if (equal? (unbox kept-file) file) (unbox kept) null))

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

(define (parse-hunks text)
  (for/list ([m (in-list (regexp-match* #px"(?m:^@@ -[0-9]+(?:,([0-9]+))? \\+([0-9]+)(?:,([0-9]+))? @@)" text #:match-select values))])
    (define old (if (cadr m) (string->number (cadr m)) 1))
    (define at (string->number (caddr m)))
    (define new (if (cadddr m) (string->number (cadddr m)) 1))
    (cond [(= new 0) (list at at "-")]
          [(= old 0) (list at (+ at new -1) "+")]
          [else (list at (+ at new -1) "=")])))

(define (gutter-refresh-maybe file again)
  (when (and (unbox paint-ready) (not (unbox busy))
             (or (not (equal? (unbox kept-file) file))
                 (>= (- (current-seconds) (unbox stamp)) 15)))
    (define first? (zero? (unbox stamp)))
    (set-box! busy #t)
    (set-box! stamp (current-seconds))
    (thread
     (lambda ()
       (void)
       (define hunks (with-handlers ([(lambda (e) #t) (lambda (e) null)]) (parse-hunks (git-diff file))))
       (define changed? (not (and (equal? (unbox kept-file) file) (equal? hunks (unbox kept)))))
       (set-box! kept hunks)
       (set-box! kept-file file)
       (set-box! busy #f)
       (when changed? (again))))))

(define (gutter-stale!) (set-box! stamp 1))

(provide gutter-stale! gutter-hunks gutter-refresh-maybe)
