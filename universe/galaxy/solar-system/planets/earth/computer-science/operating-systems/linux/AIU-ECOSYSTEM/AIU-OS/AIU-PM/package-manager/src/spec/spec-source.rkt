#lang racket/base
;; spec-source.rkt -- where a package comes from: the (git URL COMMIT)
;; pin and the two dependency lists, deps and build-deps. No I/O; the
;; syntax arrives already read, so every refusal can name a line.
;;
;; Split out of spec-read.rkt, which did four jobs in one file. The
;; direction is downward only: field-args, fail and the value
;; converters come from spec-fields.rkt, which is the base of the split.
;; That is why this file knows nothing about build steps or install
;; forms -- those are spec-build-steps.rkt, and it depends on the same
;; base rather than on this file.

(require "spec.rkt"
         "spec-fields.rkt")

(provide
 ;; syntax -> source
 read-source
 ;; syntax -> (listof dep)
 read-deps
 ;; syntax -> (listof dep), same shape as deps, build-time only
 read-build-deps)

;; ---------------------------------------------------------------------------
;; Field readers (each returns plain data for the struct)

;; syntax -> source
(define (read-source form)
  (if (local-source-form? form)
      (read-local-source form)
      (read-git-source form)))

(define (local-source-form? form)
  (define inner (syntax->list (car (field-args form 1 (quote source)))))
  (and inner
       (= (length inner) 2)
       (eq? (syntax->datum (car inner)) (quote local))))

(define (read-local-source form)
  (define inner (syntax->list (car (field-args form 1 (quote source)))))
  (define path (syntax->datum (cadr inner)))
  (unless (and (string? path) (> (string-length path) 0))
    (fail (cadr inner) "local source must be a nonempty path string"))
  (local-source path))

(define (read-git-source form)
  (define (v) (car (field-args form 1 'source)))
  (define inner (syntax->list (v)))
  (unless (and inner (= (length inner) 3)
               (eq? (syntax->datum (car inner)) 'git))
    (fail (v) "source must be (git URL COMMIT)"))
  (source (convert-url (cadr inner)) (convert-commit (caddr inner))))

;; syntax -> (listof dep)
(define (read-deps form)
  (define vals (field-args form 1 'deps))
  (define items (syntax->list (car vals)))
  (unless items
    (fail (car vals) "deps must be a list"))
  (for/list ([item (in-list items)])
    (define pair (syntax->list item))
    (if (and pair (= (length pair) 2))
        (dep (convert-name (car pair))
             (convert-version (cadr pair)))
        (fail item "dep must be (NAME VERSION)"))))

;; syntax -> (listof dep), same shape as deps, build-time only
(define (read-build-deps form)
  (define vals (field-args form 1 'build-deps))
  (define items (syntax->list (car vals)))
  (unless items
    (fail (car vals) "build-deps must be a list"))
  (for/list ([item (in-list items)])
    (define pair (syntax->list item))
    (if (and pair (= (length pair) 2))
        (dep (convert-name (car pair))
             (convert-version (cadr pair)))
        (fail item "build-dep must be (NAME VERSION)"))))
