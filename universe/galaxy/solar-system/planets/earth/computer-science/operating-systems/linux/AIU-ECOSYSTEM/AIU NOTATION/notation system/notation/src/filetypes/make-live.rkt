#lang racket/base
;; make-live.rkt -- writes one starter page per file type into types/.
;; Why: a starter page generated from the type cannot drift from the type.
;; Called by: a person, from "notation system/": racket notation/src/filetypes/make-live.rkt
(require racket/file
         racket/runtime-path
         "filetypes.rkt")

;; The folder the starter pages are written to.
(define-runtime-path live-dir "../../../../types")

;; allowed? answers whether a type may use a block name.
(define (allowed? t name)
  (define names (file-type-allowed-blocks t))
  (or (not names) (and (member name names) #t)))

;; block-text writes one block: its start line, its body lines and its end line.
(define (block-text name lines)
  (string-append name " start\n"
                 (apply string-append (map (lambda (l) (string-append l "\n")) lines))
                 name " end\n\n"))

;; starter-page builds the text of one type's starter page from what the type allows.
(define (starter-page t)
  (define name (file-type-name t))
  (string-append
   (block-text "title" (list (string-append "kind: " name)
                             (string-append "tags: " name)
                             (string-append "A new " name " page")))
   (if (allowed? t "paragraph") (block-text "paragraph" (list "Write here.")) "")
   (if (allowed? t "section")
       (block-text "section"
                   (list (block-text "title" (list "First section"))
                         (if (allowed? t "paragraph") (block-text "paragraph" (list "Sections nest.")) "")))
       "")
   (if (allowed? t "comment") (block-text "comment" (list (file-type-description t))) "")))

;; main writes a starter page for every type that loads.
(module+ main
  (make-directory* live-dir)
  (for ([(name t) (in-hash (load-file-types))])
    (define file (build-path live-dir (string-append name ".aiu")))
    (display-to-file (starter-page t) file #:exists 'truncate)
    (printf "wrote ~a\n" file)))
