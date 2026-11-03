#lang racket/base

(require racket/list racket/string racket/path "../../commands/commands.rkt" "tabs.rkt" "tabs-folders.rkt")

(provide)

(define (tabs-go! target)
  (set-box! tab-current target)
  (set-box! tab-switch target)
  (cons #f ""))

(define (tabs-step delta)
  (define files (unbox tab-files))
  (define i (index-of files (unbox tab-current)))
  (if (or (not i) (< (length files) 2))
      (cons #t "one tab")
      (tabs-go! (list-ref files (modulo (+ i delta) (length files))))))

(define (command-tab-prev session words) (tabs-step -1))

(define (command-tab-next session words) (tabs-step 1))

(define (command-tab-open session words)
  (define file (path->string (path->complete-path (session-file session))))
  (define dir (tabs-parent file))
  (define names
    (if dir
        (with-handlers ([(lambda (e) #t) (lambda (e) null)])
          (sort (for/list ([e (in-list (directory-list dir))]
                           #:when (regexp-match? #rx"[.]aiu$" (path->string e)))
                  (path->string (build-path dir e)))
                string<?))
        null))
  (define fresh (filter (lambda (p) (not (member p (unbox tab-files)))) names))
  (cond
    [(null? fresh) (cons #t "no other page in this folder")]
    [else
     (set-box! tab-files (append (unbox tab-files) (list (car fresh))))
     (tabs-go! (car fresh))]))

(define (command-tab-close session words)
  (define files (unbox tab-files))
  (define cur (unbox tab-current))
  (cond
    [(< (length files) 2) (cons #t "the last tab stays")]
    [else
     (define i (or (index-of files cur) 0))
     (define rest (remove cur files))
     (set-box! tab-files rest)
     (tabs-go! (list-ref rest (min i (sub1 (length rest)))))]))

(define (tabs-put-place! p)
  (set-box! tab-place p)
  (set-box! tab-saved p))

(define (command-tab-place-next session words)
  (define now (if (string=? (unbox tab-place) "hidden") (unbox tab-saved) (unbox tab-place)))
  (tabs-put-place! (if (string=? now "top") "bottom" "top"))
  (cons #t (format "tabs: ~a" (unbox tab-place))))

(define (command-tab-top session words) (tabs-put-place! "top") (cons #t "tabs: top"))

(define (command-tab-bottom session words) (tabs-put-place! "bottom") (cons #t "tabs: bottom"))

(define (command-tab-join session words)
  (set-box! tab-joined (not (unbox tab-joined)))
  (cons #t (if (unbox tab-joined) "tabs: joined" "tabs: apart")))

(define (command-tab-hide session words)
  (cond [(string=? (unbox tab-place) "hidden") (set-box! tab-place (unbox tab-saved))]
        [else (set-box! tab-saved (unbox tab-place))
              (set-box! tab-place "hidden")])
  (cons #t (format "tabs: ~a" (unbox tab-place))))

(define (command-tab-less session words)
  (set-box! tab-count (max 1 (sub1 (unbox tab-count))))
  (cons #t (format "tab level: ~a" (unbox tab-count))))

(define (command-tab-more session words)
  (set-box! tab-count (min 3 (add1 (unbox tab-count))))
  (cons #t (format "tab level: ~a" (unbox tab-count))))

(define (command-tab-mode session words)
  (set-layer! session "tab")
  (cons #t "layer: tab"))

(define (command-tab-level-mode session words)
  (set-layer! session "tab-level")
  (cons #t "layer: tab-level"))

(hash-set! commands "tab-mode" command-tab-mode)
(hash-set! commands "tab-level-mode" command-tab-level-mode)
(hash-set! commands "tab-prev" command-tab-prev)
(hash-set! commands "tab-next" command-tab-next)
(hash-set! commands "tab-open" command-tab-open)
(hash-set! commands "tab-close" command-tab-close)
(hash-set! commands "tab-place-next" command-tab-place-next)
(hash-set! commands "tab-top" command-tab-top)
(hash-set! commands "tab-bottom" command-tab-bottom)
(hash-set! commands "tab-join" command-tab-join)
(hash-set! commands "tab-hide" command-tab-hide)
(hash-set! commands "tab-less" command-tab-less)
(hash-set! commands "tab-more" command-tab-more)
