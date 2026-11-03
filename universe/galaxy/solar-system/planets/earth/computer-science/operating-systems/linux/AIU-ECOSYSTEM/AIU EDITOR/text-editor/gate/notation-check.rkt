#lang racket/base

(require racket/file
         racket/list
         racket/path
         racket/string
         "../editor/notation/document.rkt"
         "../editor/notation/host.rkt")

(define project-dir
  (let loop ([at (simplify-path (current-directory))])
    (define up (simplify-path (build-path at "..")))
    (cond
      [(and (directory-exists? (build-path at "editor"))
            (directory-exists? (build-path at "gate")))
       at]
      [(string=? (path->string at) (path->string up)) at]
      [else (loop up)])))

(define types-dir
  (simplify-path (build-path project-dir ".." ".." "AIU NOTATION" "types")))

(define scratch-journal
  (build-path (find-system-path 'temp-dir) "notation-check.journal"))

(define (page-file? path)
  (string-suffix? (path->string path) ".aiu"))

(define (starter-pages)
  (if (directory-exists? types-dir)
      (sort (filter page-file?
                    (map (lambda (name) (build-path types-dir name))
                         (directory-list types-dir)))
            (lambda (a b) (string<? (path->string a) (path->string b))))
      '()))

(define (outside-text? block text)
  (or (< (block-start block) 0)
      (>= (block-start block) (string-length text))
      (> (block-end block) (string-length text))
      (>= (block-start block) (block-end block))))

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

(define (check-page path)
  (define got (page-of path scratch-journal))
  (if (page? got)
      (page-faults-of path got (file->string path))
      (format "the page ~a cannot be read: ~a" path (page-refusal-text got))))

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

(define (check-render page)
  (define rendered (render-of page scratch-journal))
  (define lines (string-split rendered "\n"))
  (define markers
    (filter (lambda (line)
              (or (string-suffix? (string-trim line) " start")
                  (string-suffix? (string-trim line) " end")))
            lines))
  (cond
    [(string=? (string-trim rendered) "")
     (format "the view of ~a is empty" page)]
    [(not (null? markers))
     (format "the view of ~a still carries the marker ~s" page (car markers))]
    [else #f]))

(define (check-version)
  (define got (read-page "NOTATION-DOCUMENT 2\nend\n"))
  (cond
    [(page? got) "a NOTATION-DOCUMENT 2 is read as a page, and it must be refused"]
    [(string=? got "") "the refusal of a NOTATION-DOCUMENT 2 says nothing"]
    [else #f]))

(define (main)
  (define pages (starter-pages))
  (cond
    [(null? pages)
     (printf "NOTHING-TO-CHECK notation-check: there are no pages at ~a\n" types-dir)
     (exit 0)]
    [else
     (define faults
       (append (filter values (map check-page pages))
               (filter values (list (check-planted) (check-version) (check-render (car pages))))))
     (if (null? faults)
         (begin
           (printf "OK notation-check — ~a starter pages read through the engine: a title first, no fault, every block inside the text; a planted fault names its line and what to do; a document that is not version 1 is refused\n"
                   (length pages))
           (exit 0))
         (begin
           (for-each (lambda (fault) (printf "NOTATION — ~a\n" fault)) faults)
           (printf "NOTATION — ~a faults\n" (length faults))
           (exit 1)))]))

(module+ main
  (main))
