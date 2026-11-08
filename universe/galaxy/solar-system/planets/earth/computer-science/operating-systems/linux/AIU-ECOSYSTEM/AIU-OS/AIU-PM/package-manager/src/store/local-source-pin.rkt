#lang racket/base
;; local-source-pin.rkt -- turns a (local PATH) source into a plain source:
;; url local:/absolute/folder, commit = the tree fingerprint of the folder.
;; Relative paths are taken from the directory pm runs in.

(require racket/contract/base
         "../spec/spec.rkt"
         "./content-address.rkt")

(provide
 (contract-out
  ;; (listof spec) -> (listof spec), every local source pinned, git sources untouched
  [pin-local-sources (-> (listof spec?) (listof spec?))]
  ;; folder names left out of the fingerprint and of the copy
  [local-source-skipped-folders (listof string?)]))

(define local-source-skipped-folders (list "compiled" "target" ".git" "node_modules"))

;; string -> string, absolute and simplified folder
(define (absolute-folder text)
  (path->string (simplify-path (path->complete-path (string->path text)))))

;; spec -> spec
(define (pin-one specification)
  (define found (spec-source specification))
  (if (local-source? found)
      (let ([folder (absolute-folder (local-source-path found))])
        (struct-copy spec specification
                     [source (source (string-append "local:" folder)
                                     (tree-hash folder local-source-skipped-folders))]))
      specification))

;; (listof spec) -> (listof spec)
(define (pin-local-sources specifications)
  (map pin-one specifications))
