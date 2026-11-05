#lang racket/base
(require racket/string racket/file)
(provide float-names float-preset-names float-rect float-next-preset float-next-share float-grow-share float-shrink-share float-pane-id-of float-tabs-text float-file-path float-visible float-active float-share float-root float-current-file)

(define float-names (quote ("todo" "journal" "notes")))
(define float-preset-names (quote ("small" "medium" "large" "full")))
(define float-preset-shares (quote (40 60 80 100)))

(define (float-next-preset preset) (modulo (add1 preset) (length float-preset-shares)))
(define (float-pane-id-of index) (- -1 index))
(define (float-next-share share)
  (or (for/first ([s (in-list float-preset-shares)] #:when (> s share)) s) (car float-preset-shares)))
(define (float-grow-share share) (min 100 (+ share 10)))
(define (float-shrink-share share) (max 30 (- share 10)))

(define (float-rect preset columns rows)
  (define share preset)
  (define narrow? (< columns 100))
  (define width
    (max (min columns 12)
         (cond
           [(= share 100) columns]
           [narrow? (- columns 2)]
           [else (quotient (* columns share) 100)])))
  (define height (max (min rows 5) (quotient (* rows share) 100)))
  (values (quotient (- columns width) 2) (quotient (- rows height) 2) width height))

(define (float-tabs-text active)
  (string-join
   (for/list ([name (in-list float-names)] [i (in-naturals)])
     (if (= i active) (string-append "[" name "]") name))
   " "))

(define (two-digits n) (if (< n 10) (string-append "0" (number->string n)) (number->string n)))

(define (today-text)
  (define d (seconds->date (current-seconds)))
  (string-append (number->string (date-year d)) "-" (two-digits (date-month d)) "-" (two-digits (date-day d))))

(define (file-created-when-missing path text)
  (define-values (base name dir?) (split-path path))
  (make-directory* base)
  (unless (file-exists? path) (display-to-file text path))
  path)

(define (float-file-path name root)
  (cond
    [(string=? name "todo") (build-path root "AIU TERMINAL MULTIPLEXER" "todo.aiu")]
    [(string=? name "journal")
     (define day (today-text))
     (file-created-when-missing
      (build-path root "journal" (string-append day ".aiu"))
      (string-append "title start\nkind: journal\ntags: journal\nJournal " day "\ntitle end\n"))]
    [else
     (file-created-when-missing
      (build-path root "notes.aiu")
      "title start\nkind: plan\ntags: notes\nNOTES\ntitle end\n")]))

(define float-visible (box #f))
(define float-active (box 0))
(define float-share (box 100))

(define (float-root)
  (define raw (environment-variables-ref (current-environment-variables) #"AIU_ROOT"))
  (if raw (bytes->path raw) (current-directory)))

(define (float-current-file)
  (float-file-path (list-ref float-names (unbox float-active)) (float-root)))
