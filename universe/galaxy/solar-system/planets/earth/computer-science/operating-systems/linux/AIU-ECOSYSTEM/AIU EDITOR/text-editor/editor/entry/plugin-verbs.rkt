#lang racket/base

(require racket/list
         racket/path
         racket/string
         "../plugins/loader.rkt"
         "../plugins/manifest.rkt"
         "../plugins/pm.rkt"
         "../plugins/seam.rkt"
         "../narration/print-console-shared.rkt")

(define (plugin-verb args)
  (define names (plugin-names))
  (if (null? names)
      (print-line "the editor knows no plugin: the notation is not registered here yet")
      (for-each
       (lambda (name)
         (define state (plugin-state name))
         (define manifest (hash-ref state 'manifest #f))
         (print-line (format "~a  version: ~a  package: ~a  provides: ~a"
                              name
                              (if manifest (hash-ref manifest 'version "?") "?")
                              (hash-ref state 'package "?")
                              (if manifest
                                  (string-join (hash-ref manifest 'provides '()) " ")
                                  "?")))
         (print-line (format "  pm: ~a" (plugin-verdict state))))
       names)))

(define (plugin-register-verb args)
  (cond
    [(null? args)
     (print-line "the plugin was not registered: give the path of its manifest")]
    [else
     (define path (car args))
     (define manifest (read-manifest-file path))
     (cond
       [(not manifest)
        (print-line (format "the plugin was not registered: ~a could not be read as a manifest" path))]
       [else
        (define missing (manifest-missing manifest))
        (if (null? missing)
            (begin
              (write-manifest manifest)
              (print-line (format "the plugin is registered: ~a"
                                  (hash-ref manifest 'name "unnamed"))))
            (print-line (format "the plugin was not registered: the manifest misses ~a"
                                (string-join (map symbol->string missing) ", "))))])]))

(define (plugin-install-verb args)
  (cond
    [(null? args)
     (print-line "the plugin was not installed: give its name")]
    [else
     (define name (car args))
     (define state (plugin-state name))
     (cond
       [(not (hash-ref state 'known #f))
        (print-line (format "the plugin ~a is not registered here: ~a"
                            name (string-join (map symbol->string (hash-ref state 'missing '())) ", ")))]
       [else
        (define spec (hash-ref (hash-ref state 'manifest #f) 'spec ""))
        (define answer (pm-apply spec #t))
        (if (hash-ref answer 'ok #f)
            (print-line (format "pm installed the plugin ~a: ~a" name (string-trim (hash-ref answer 'out ""))))
            (print-line (format "the plugin ~a was not installed: ~a"
                                name (string-trim (hash-ref answer 'err "")))))])]))

(define (plugin-call-verb args)
  (cond
    [(< (length args) 2)
     (print-line "the plugin was not called: give its name and the call")]
    [else
     (define name (car args))
     (define call (cadr args))
     (define rest (cddr args))
     (define answer (call-plugin name call (make-args rest)))
     (if (hash-ref answer 'ok #f)
         (begin
           (print-line (format "the plugin ~a answered the call ~a" name call))
           (print-line (string-join (describe-answer (hash-ref answer 'answer #f)) " ")))
         (print-line (hash-ref answer 'error "the plugin did not answer")))]))

(define (make-args words)
  (for/hash ([word (in-list words)])
    (values word word)))

(define (describe-answer answer)
  (if (not answer)
      '()
      (for/list ([key (in-list (sort (hash-keys answer) symbol<?))])
        (format "~a: ~a" key (hash-ref answer key)))))

(provide plugin-verb
         plugin-register-verb
         plugin-install-verb
         plugin-call-verb)
