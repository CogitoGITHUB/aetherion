#lang racket/base
(require racket/list racket/string "tabs-folders-shared.rkt")
(provide nv-text nv-step nv-move nv-hide nv-open nv-new
         nv-rename nv-remove nv-touch!)
(define orders (make-hasheq))
(define hiddens (make-hasheq))
(define cache (box #f))
(define (nv-touch!) (set-box! cache #f))
(define (arrange names kind cur)
  (define hidden (hash-ref hiddens kind (list)))
  (define shown
    (filter (lambda (n) (or (equal? n cur) (not (member n hidden))))
            names))
  (define known
    (filter (lambda (n) (member n shown))
            (hash-ref orders kind (list))))
  (append known (filter (lambda (n) (not (member n known))) shown)))
(define (where cwd)
  (define base
    (if (and (string? cwd) (not (string=? cwd ""))
             (directory-exists? cwd))
        cwd
        (path->string (current-directory))))
  (define file (path->string (build-path base "shell")))
  (define root (tabs-root file))
  (values root (tabs-parent root) (tabs-project file root)
          (tabs-last root)))
(define (listing kind cwd)
  (define-values (root up proj ws) (where cwd))
  (cond
    [(eq? kind (quote project))
     (values (arrange (tabs-dirs root) kind proj) proj root)]
    [up (values (arrange (tabs-dirs up) kind ws) ws up)]
    [else (values (list) ws #f)]))
(define (build cwd)
  (define-values (wn wc wp) (listing (quote workspace) cwd))
  (define-values (pn pc pp) (listing (quote project) cwd))
  (string-join
   (list (string-join wn "\u001f")
         (number->string (or (index-of wn wc) 0))
         (string-join pn "\u001f")
         (number->string (or (index-of pn pc) 0)))
   "\u001d"))
(define (nv-text cwd)
  (define c (unbox cache))
  (define now (current-inexact-milliseconds))
  (cond
    [(and c (equal? (car c) cwd) (< (- now (cadr c)) 2000))
     (caddr c)]
    [else
     (define s (build cwd))
     (set-box! cache (list cwd now s))
     s]))
(define (nv-step kind cwd delta)
  (define-values (names cur parent) (listing kind cwd))
  (define i (index-of names cur))
  (cond
    [(or (not i) (not parent) (< (length names) 2)) #f]
    [else
     (path->string
      (build-path parent
                  (list-ref names
                            (modulo (+ i delta) (length names)))))]))
(define (nv-move kind cwd delta)
  (define-values (names cur parent) (listing kind cwd))
  (define i (index-of names cur))
  (when (and i (< -1 (+ i delta) (length names)))
    (define v (list->vector names))
    (define j (+ i delta))
    (vector-set! v i (vector-ref v j))
    (vector-set! v j cur)
    (hash-set! orders kind (vector->list v)))
  (nv-touch!))
(define (nv-hide kind cwd)
  (define-values (names cur parent) (listing kind cwd))
  (define target (nv-step kind cwd 1))
  (cond
    [target
     (hash-set! hiddens kind (cons cur (hash-ref hiddens kind (list))))
     (nv-touch!)
     target]
    [else #f]))
(define (nv-open kind)
  (hash-set! hiddens kind (list))
  (nv-touch!))
(define (nv-new kind cwd name)
  (define-values (names cur parent) (listing kind cwd))
  (define nm
    (if (string=? name "")
        (let loop ([n (add1 (length names))])
          (if (directory-exists? (build-path parent (number->string n)))
              (loop (add1 n))
              (number->string n)))
        name))
  (define dir (and parent (build-path parent nm)))
  (cond
    [(or (not dir) (directory-exists? dir) (file-exists? dir)) #f]
    [else
     (with-handlers ([void (lambda (e) #f)])
       (make-directory dir)
       (nv-touch!)
       (path->string dir))]))
(define (nv-rename kind cwd name)
  (define-values (names cur parent) (listing kind cwd))
  (define old (and parent (build-path parent cur)))
  (define new
    (and parent (not (string=? name "")) (build-path parent name)))
  (cond
    [(or (not old) (not new) (directory-exists? new)
         (file-exists? new)) #f]
    [else
     (with-handlers ([void (lambda (e) #f)])
       (rename-file-or-directory old new)
       (hash-set! orders kind
                  (map (lambda (n) (if (equal? n cur) name n))
                       (hash-ref orders kind (list))))
       (nv-touch!)
       (path->string new))]))
(define (nv-remove kind cwd)
  (define-values (names cur parent) (listing kind cwd))
  (define target (nv-step kind cwd 1))
  (define dir (and parent (build-path parent cur)))
  (define gone
    (and parent (build-path parent (string-append ".removed-" cur))))
  (cond
    [(or (not target) (not dir) (directory-exists? gone)
         (file-exists? gone)) #f]
    [else
     (with-handlers ([void (lambda (e) #f)])
       (rename-file-or-directory dir gone)
       (nv-touch!)
       target)]))