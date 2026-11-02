#lang racket/base
;; One job: the block edit of the live session - move the point from block to
;; block, open the lit block as raw text, and keep the point inside it while it
;; is edited. It requires blockview.rkt (the block view); blockview.rkt never
;; requires this file.

(require racket/list
         racket/string
         "../commands/commands.rkt"
         "../notation/document.rkt"
         "../notation/host.rkt"
         "blockview.rkt")

;; blockview-clamp! puts the point back inside the block being edited.
(define (blockview-clamp! session start)
  (define got (page-of (session-file session) (session-journal session)))
  (define b
    (and (page? got)
         (for/first ([x (in-list (page-blocks got))] #:when (= (block-start x) start))
           x)))
  (when b
    (define p (the-point session))
    (cond
      [(< p (unbox edit-lo)) (move-to session (unbox edit-lo))]
      [(> p (blockview-hi session b)) (move-to session (blockview-hi session b))]
      [else (void)])))

;; block-guard runs one command of the live session. While a block is edited the
;; backspace stops at the start of the block, so no text outside it is taken, and
;; the point is put back inside the block after every command.
(define (block-guard session line run)
  (define start (unbox edit-start))
  (cond
    [(not (and start (string=? (the-layer session) "write"))) (run)]
    [(and (string=? line "delete") (<= (the-point session) (unbox edit-lo))) #t]
    [else
     (define result (run))
     (blockview-clamp! session start)
     result]))

;; blockview-first-content answers the offset of the second line of a block, where its
;; text begins, or the start of the block when it has one line.
(define (blockview-first-content raw b)
  (define bs (string->bytes/utf-8 raw))
  (define end (min (block-end b) (bytes-length bs)))
  (let loop ([i (block-start b)])
    (cond
      [(>= i end) (block-start b)]
      [(= (bytes-ref bs i) 10) (min end (add1 i))]
      [else (loop (add1 i))])))

;; blockview-step moves the point to the next block (direction 1) or the previous one
;; (direction -1). A file that is not a page scrolls the view instead.
(define (blockview-step session words direction fallback)
  (define got (and (blockview-aiu? session)
                   (page-of (session-file session) (session-journal session))))
  (cond
    [(not (page? got)) ((hash-ref commands fallback) session words)]
    [else
     (define blocks (filter blockview-kind-match? (blockview-drawn (page-blocks got))))
     (define p (the-point session))
     (define current (blockview-inside blocks p))
     (define here (if current (block-start current) #f))
     (define candidates
       (cond
         [(and here (> direction 0)) (filter (lambda (b) (> (block-start b) here)) blocks)]
         [(and here (< direction 0)) (filter (lambda (b) (< (block-start b) here)) blocks)]
         [(> direction 0) (filter (lambda (b) (> (block-start b) p)) blocks)]
         [else (filter (lambda (b) (< (block-start b) p)) blocks)]))
     (cond
       [(null? candidates) (cons #t "no block there")]
       [else
        (define target
          (if (> direction 0)
              (argmin block-start candidates)
              (argmax block-start candidates)))
        (move-to session (block-start target))
        (cons #t (format "block: ~a" (block-name target)))])]))

;; blockview-command-up lights the block before this one.
(define (blockview-command-up session words)
  (blockview-step session words -1 "view-up"))

;; blockview-command-down lights the block after this one.
(define (blockview-command-down session words)
  (blockview-step session words 1 "view-down"))

;; blockview-command-edit opens the lit block as raw text in the write layer. Every
;; other block stays drawn. A block whose lines cannot be told opens the whole
;; page to write, as the write layer always did.
(define (blockview-command-edit session words)
  (define got (and (blockview-aiu? session)
                   (page-of (session-file session) (session-journal session))))
  (cond
    [(not (page? got)) (cons #t "block edit needs a page of the notation that can be read")]
    [else
     (define raw (session-text session))
     (define lines (string-split (drawn-view session raw (blockview-width)) "\n" #:trim? #f))
     (define ranges (blockview-ranges got lines))
     (define target (blockview-target (page-blocks got) (the-point session) ranges))
     (set-layer! session "write")
     (cond
       [target
        (set-box! edit-start (block-start target))
         (set-box! edit-mode "raw")
         (set-box! edit-lo (block-start target))
        (move-to session (blockview-first-content raw target))
        (cons #t (format "editing the ~a block: escape draws the page again"
                         (block-name target)))]
       [else
        (set-box! edit-start #f)
        (cons #t "no block is lit here: the whole page is open to write")])]))

;; blockview-content answers the byte range of the text lines of a leaf block: from the
;; second line to the end of the line before the end line. Nothing when the block
;; has no text line.
(define (blockview-content raw b)
  (define bs (string->bytes/utf-8 raw))
  (define end (min (block-end b) (bytes-length bs)))
  (define lo (blockview-first-content raw b))
  (define trimmed
    (let loop ([e end])
      (if (and (> e lo) (= (bytes-ref bs (sub1 e)) 10)) (loop (sub1 e)) e)))
  (define last-start
    (let loop ([i trimmed])
      (cond
        [(<= i lo) lo]
        [(= (bytes-ref bs (sub1 i)) 10) i]
        [else (loop (sub1 i))])))
  (if (> last-start lo) (cons lo (sub1 last-start)) #f))

;; blockview-hi answers the highest byte the point may reach while a block is edited.
(define (blockview-hi session b)
  (define span
    (and (string=? (unbox edit-mode) "text")
         (blockview-content (session-text session) b)))
  (if span (cdr span) (block-end b)))

;; The block keys are added to the command table when this module is loaded,
;; before the wrapper below reads the block-edit key.
(hash-set! commands "block-up" blockview-command-up)
(hash-set! commands "block-down" blockview-command-down)
(hash-set! commands "block-edit" blockview-command-edit)

;; Opening the block edit drops the extra cursors: the block edit is one place.
(for-each
 (lambda (name)
   (hash-set! commands name
              (let ([orig (hash-ref commands name)])
                (lambda (session words) (multi-clear!) (orig session words)))))
 (list "block-edit"))

;; The block edit, for the live screen and the block text above it.
(provide block-guard blockview-clamp! blockview-first-content blockview-step blockview-command-up blockview-command-down
         blockview-command-edit blockview-content blockview-hi)
