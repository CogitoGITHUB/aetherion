#lang racket/base

(require racket/list
         racket/string)

(struct bundle (header selection file position address why) #:transparent)

(define boundary-version "1")

(define (make-bundle program project target selection file position address why)
  (if (string=? (string-trim why) "")
      #f
      (bundle (hash 'boundary boundary-version
                     'program program
                     'project project
                     'target target)
              selection
              file
              position
              address
              why)))

(define (bundle-document bundle)
  (define header (bundle-header bundle))
  (define references
    (filter values
            (list (and (bundle-file bundle)
                        (hash 'path (bundle-file bundle)))
                  (and (bundle-position bundle)
                        (hash 'position (bundle-position bundle)))
                  (and (bundle-address bundle)
                        (hash 'address (bundle-address bundle)))
                  (and (bundle-selection bundle)
                        (hash 'selection (bundle-selection bundle))))))
  (list header (hash 'references references)))

(define (bundle-target bundle)
  (hash-ref (bundle-header bundle) 'target ""))

(define (bundle-text bundle)
  (string-join (bundle-lines bundle) "\n"))

(define (bundle-lines bundle)
  (define document (bundle-document bundle))
  (define header (car document))
  (define references (hash-ref (cadr document) 'references))
  (append
   (list (format "boundary: ~a  program: ~a  project: ~a  target: ~a"
                 (hash-ref header 'boundary)
                 (hash-ref header 'program)
                 (hash-ref header 'project)
                 (hash-ref header 'target)))
   (list (format "why: ~a" (bundle-why bundle)))
   (for/list ([reference (in-list references)])
     (string-join
      (for/list ([key (in-list (sort (hash-keys reference) string<?))])
        (format "~a: ~a" key (hash-ref reference key)))
      "  "))))

(provide bundle
         bundle?
         bundle-header
         bundle-selection
         bundle-file
         bundle-position
         bundle-address
         bundle-why
         boundary-version
         make-bundle
         bundle-document
         bundle-lines
         bundle-text
         bundle-target)
