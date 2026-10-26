#lang racket/base
;; One job: the notation check — the editor reads AIU NOTATION pages through
;; the notation engine, and this stage proves it on real pages.
;; Registered in plan/package-tree.org; lands with TODO item 21.
;;
;; The four proofs, each one real:
;;   1. every starter page of the notation project parses through the seam,
;;      with the first block a title and no fault;
;;   2. a page with text outside any block answers the faults it has, with the
;;      line and the thing to do;
;;   3. every block sits inside the text: the offsets are bytes that exist;
;;   4. a document that is not version 1 is refused by name, never read as if
;;      it were version 1.
;;
;; The check runs from the project directory, so the package and the notation
;; project are reached by relative paths.

(require racket/file
         racket/list
         racket/path
         racket/string
         "../editor/src/notation/document.rkt"
         "../editor/src/notation/host.rkt")

;; project-dir is the editor's directory: the one that holds the package and
;; the gate. The search walks up from where the check runs.
(define project-dir
  (let loop ([at (simplify-path (current-directory))])
    (define up (simplify-path (build-path at "..")))
    (cond
      [(and (directory-exists? (build-path at "editor" "src"))
            (directory-exists? (build-path at "gate")))
       at]
      [(string=? (path->string at) (path->string up)) at]
      [else (loop up)])))

;; types-dir is the notation project's starter pages: the kinds the notation
;; ships, and the pages a person actually opens first.
(define types-dir
  (simplify-path (build-path project-dir ".." ".." "AIU NOTATION" "types")))

;; scratch-journal is the journal the check asks with: no session is opened,
;; so nothing is written and the journal stays empty.
(define scratch-journal
  (build-path (find-system-path 'temp-dir) "notation-check.journal"))

;; page-file? answers whether a path is a page of the notation: the extension
;; is the whole test.
(define (page-file? path)
  (string-suffix? (path->string path) ".aiu"))

;; starter-pages answers the pages of the notation project, sorted, so the
;; check reads the same way every run.
(define (starter-pages)
  (if (directory-exists? types-dir)
      (sort (filter page-file?
                    (map (lambda (name) (build-path types-dir name))
                         (directory-list types-dir)))
            (lambda (a b) (string<? (path->string a) (path->string b))))
      '()))

;; outside-text? answers whether a block's offsets are outside a text: a start
;; before the first byte, an end past the last, or an empty block.
(define (outside-text? block text)
  (or (< (block-start block) 0)
      (>= (block-start block) (string-length text))
      (> (block-end block) (string-length text))
      (>= (block-start block) (block-end block))))

;; page-faults-of answers what is wrong with a page that parsed, or nothing
;; when it is in order: a title first, no fault, every block inside the text.
(define (page-faults-of path got text)
  (define blocks (page-blocks got))
  (define faults (page-faults got))
  (define outside (filter (lambda (b) (outside-text? b text)) blocks))
  (cond
    [(null? blocks)
     (format "the page ~a has no blocks" path)]
    [(not (string=? (block-name (car blocks)) "title"))
     (format "the page ~a starts with ~a, and a page starts with a title"
             path (block-name (car blocks)))]
    [(not (null? faults))
     (format "the page ~a has ~a faults, and a starter page has none: ~a"
             path (length faults) (fault-what (car faults)))]
    [(null? outside) #f]
    [else
     (format "the block ~a of the page ~a sits outside the text: bytes ~a..~a of ~a"
             (block-name (car outside)) path
             (block-start (car outside)) (block-end (car outside))
             (string-length text))]))

;; check-page answers what is wrong with one page, or nothing when it is in
;; order. A page that cannot be read is a fault of its own, and the refusal is
;; printed as the reason.
(define (check-page path)
  (define got (page-of path scratch-journal))
  (if (page? got)
      (page-faults-of path got (file->string path))
      (format "the page ~a cannot be read: ~a" path (page-refusal-text got))))

;; check-planted answers what is wrong with the proof of a planted fault: a
;; page with text outside every block must answer at least one fault, and the
;; fault must name its line and what to do.
(define (check-planted)
  (define planted
    (build-path (find-system-path 'temp-dir) "notation-planted.aiu"))
  (display-to-file "stray text before any block\n\ntitle start\nA page\n"
                   planted #:exists 'replace)
  (define got (page-of planted scratch-journal))
  (cond
    [(not (page? got))
     (format "the planted page cannot be read: ~a" (page-refusal-text got))]
    [(null? (page-faults got))
     "the planted page has stray text and the page answers no fault"]
    [else
     (define f (car (page-faults got)))
     (cond
       [(<= (fault-line f) 0)
        (format "the fault of the planted page names no line: ~a" (fault-what f))]
       [(string=? (fault-what-to-do f) "")
        (format "the fault of the planted page names nothing to do: ~a" (fault-what f))]
       [else #f])]))

;; check-version answers what is wrong with the version guard: a document that
;; is not version 1 is refused, and the refusal says something.
(define (check-version)
  (define got (read-page "NOTATION-DOCUMENT 2\nend\n"))
  (cond
    [(page? got) "a NOTATION-DOCUMENT 2 is read as a page, and it must be refused"]
    [(string=? got "") "the refusal of a NOTATION-DOCUMENT 2 says nothing"]
    [else #f]))

;; main runs the proofs and answers what is wrong, one line per fault; it exits
;; non-zero when a fault is found, and says NOTHING-TO-CHECK when the notation
;; project's pages are not there.
(define (main)
  (define pages (starter-pages))
  (cond
    [(null? pages)
     (printf "NOTHING-TO-CHECK notation-check: there are no pages at ~a\n" types-dir)
     (exit 0)]
    [else
     (define faults
       (append (filter values (map check-page pages))
               (filter values (list (check-planted) (check-version)))))
     (if (null? faults)
         (begin
           (printf "OK notation-check — ~a starter pages read through the engine: a title first, no fault, every block inside the text; a planted fault names its line and what to do; a document that is not version 1 is refused\n"
                   (length pages))
           (exit 0))
         (begin
           (for-each (lambda (fault) (printf "NOTATION — ~a\n" fault)) faults)
           (printf "NOTATION — ~a faults\n" (length faults))
           (exit 1)))]))

;; The check, for the dispatcher above.
(module+ main
  (main))
