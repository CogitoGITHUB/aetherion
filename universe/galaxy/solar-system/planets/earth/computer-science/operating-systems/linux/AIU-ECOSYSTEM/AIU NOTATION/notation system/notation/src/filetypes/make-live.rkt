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

;; block-text writes one block: its start line, its body lines and its end line, then a
;; blank line.
(define (block-text name lines)
  (string-append name " start\n"
                 (apply string-append (map (lambda (l) (string-append l "\n")) lines))
                 name " end\n\n"))

;; section-text writes one section: its title block, then the blocks inside it (already
;; text).
(define (section-text title body)
  (string-append "section start\n"
                 (block-text "title" (list title))
                 body
                 "section end\n\n"))

;; body-for writes the filler of a block: one paragraph when the type allows paragraphs.
(define (body-for t text)
  (if (allowed? t "paragraph") (block-text "paragraph" (list text)) ""))

;; sections-for writes the sections of a starter page: one for each title the type requires,
;; one generic section when it requires none, and nothing when sections are not allowed.
(define (sections-for t)
  (define titles (required-sections-of (file-type-name t)))
  (cond
    [(not (allowed? t "section")) ""]
    [(null? titles) (section-text "First section" (body-for t "Sections nest."))]
    [else
     (apply string-append
            (for/list ([title (in-list titles)])
              (section-text title (body-for t "Write here."))))]))

;; starter-page builds the text of one type's starter page from what the type allows.
(define (starter-page t)
  (define name (file-type-name t))
  (string-append
   (block-text "title" (list (string-append "kind: " name)
                             (string-append "tags: " name)
                             (string-append "A new " name " page")))
   (body-for t "Write here.")
   (sections-for t)
   (if (allowed? t "comment") (block-text "comment" (list (file-type-description t))) "")))

;; main writes a starter page for every type that loads.
(module+ main
  (make-directory* live-dir)
  (for ([(name t) (in-hash (load-file-types))])
    (define file (build-path live-dir (string-append name ".aiu")))
    (display-to-file (starter-page t) file #:exists 'truncate)
    (printf "wrote ~a\n" file)))
