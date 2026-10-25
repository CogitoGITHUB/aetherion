#lang racket/base
;; filetypes.rkt -- finds and loads every file type in the filetypes/types/ folder.
;; Why: adding a file type means adding one module to filetypes/types/, with no edit here
;; or in the engine.
;; Called by: nothing yet (to be wired into the engine).
(require racket/runtime-path "type.rkt")
(provide (all-from-out "type.rkt") load-file-types file-type-named type-modules)

;; The folder that holds one module per file type.
(define-runtime-path types-dir "types")

;; The module that defines the type at one entry of the folder: a .rkt file is the type
;; itself, a subfolder holds it in type.rkt beside its own modules. Anything else, and
;; any name starting with an underscore, is not a type: the answer is #f.
(define (entry-module entry)
  (define path (build-path types-dir entry))
  (define name (path->string entry))
  (cond
    [(regexp-match? #rx"^_" name) #f]
    [(directory-exists? path)
     (let ([main (build-path path "type.rkt")])
       (and (file-exists? main) main))]
    [(regexp-match? #rx"[.]rkt$" name) path]
    [else #f]))

;; Every file type, as a hash from its name to its file-type record.
(define (load-file-types)
  (for/hash ([entry (in-list (sort (directory-list types-dir) path<?))]
             #:when (entry-module entry))
    (let ([found (dynamic-require (entry-module entry) 'the-type)])
      (values (file-type-name found) found))))

;; One file type by name, or #f when there is no such type.
(define (file-type-named name)
  (hash-ref (load-file-types) name #f))

;; type-modules lists the module path of every file type, in folder order.
(define (type-modules)
  (for/list ([entry (in-list (sort (directory-list types-dir) path<?))]
             #:when (entry-module entry))
    (entry-module entry)))
