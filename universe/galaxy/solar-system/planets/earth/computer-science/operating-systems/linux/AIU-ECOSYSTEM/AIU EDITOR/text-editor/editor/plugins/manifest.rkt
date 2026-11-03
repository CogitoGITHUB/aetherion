#lang racket/base

(require json
         racket/file
         racket/list
         racket/path
         racket/string
         "../machine/directories.rkt")

(define plugin-dir
  (build-path (state-dir) "plugins"))

(define manifest-fields
  '(name version package spec command provides))

(define (manifest-path name)
  (build-path plugin-dir (string-append name ".json")))

(define (read-manifest name)
  (with-handlers ([exn:fail? (lambda (why) #f)])
    (define path (manifest-path name))
    (if (file-exists? path)
        (read-json (open-input-file path))
        #f)))

(define (read-manifest-file path)
  (with-handlers ([exn:fail? (lambda (why) #f)])
    (read-json (open-input-file path))))

(define (write-manifest manifest)
  (ensure-dir plugin-dir)
  (define path (manifest-path (hash-ref manifest 'name "unnamed")))
  (call-with-output-file path
    (lambda (port)
      (write-json manifest port)
      (newline port))
    #:exists 'truncate)
  manifest)

(define (manifest-field-ok? manifest field)
  (define value (hash-ref manifest field #f))
  (cond
    [(not value) #f]
    [(or (eq? field 'command) (eq? field 'provides)) (list? value)]
    [(eq? field 'name) (string? value)]
    [(eq? field 'version) (string? value)]
    [(eq? field 'package) (string? value)]
    [(eq? field 'spec) (string? value)]
    [else #t]))

(define (manifest-missing manifest)
  (if (not manifest)
      manifest-fields
      (filter (lambda (field) (not (manifest-field-ok? manifest field)))
              manifest-fields)))

(define (plugin-names)
  (if (directory-exists? plugin-dir)
      (sort (map plugin-name-of
                  (filter (lambda (path) (string-suffix? (path->string path) ".json"))
                          (directory-list plugin-dir)))
            string<?)
      '()))

(define (plugin-name-of path)
  (define name (path->string (file-name-from-path path)))
  (if (string-suffix? name ".json")
      (substring name 0 (- (string-length name) 5))
      name))

(provide plugin-dir
         manifest-fields
         manifest-path
         read-manifest
         read-manifest-file
         write-manifest
         manifest-missing
         plugin-names)
