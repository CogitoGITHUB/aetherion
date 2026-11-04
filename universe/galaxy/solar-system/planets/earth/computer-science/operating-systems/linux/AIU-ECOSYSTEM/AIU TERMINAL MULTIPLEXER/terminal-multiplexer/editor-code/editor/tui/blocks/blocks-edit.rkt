#lang racket/base

(require racket/list
         racket/string
         "../../commands/commands.rkt"
         "../../bridge/document.rkt"
         "../../bridge/host.rkt"
         "blockview.rkt")

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

(define (block-guard session line run)
  (define start (unbox edit-start))
  (cond
    [(not (and start (string=? (the-layer session) "write"))) (run)]
    [(and (string=? line "delete") (<= (the-point session) (unbox edit-lo))) #t]
    [else
     (define result (run))
     (blockview-clamp! session start)
     result]))

(define (blockview-first-content raw b)
  (define bs (string->bytes/utf-8 raw))
  (define end (min (block-end b) (bytes-length bs)))
  (let loop ([i (block-start b)])
    (cond
      [(>= i end) (block-start b)]
      [(= (bytes-ref bs i) 10) (min end (add1 i))]
      [else (loop (add1 i))])))

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

(define (blockview-command-up session words)
  (blockview-step session words -1 "view-up"))

(define (blockview-command-down session words)
  (blockview-step session words 1 "view-down"))

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

(define (blockview-hi session b)
  (define span
    (and (string=? (unbox edit-mode) "text")
         (blockview-content (session-text session) b)))
  (if span (cdr span) (block-end b)))

(hash-set! commands "block-up" blockview-command-up)
(hash-set! commands "block-down" blockview-command-down)
(hash-set! commands "block-edit" blockview-command-edit)

(for-each
 (lambda (name)
   (hash-set! commands name
              (let ([orig (hash-ref commands name)])
                (lambda (session words) (multi-clear!) (orig session words)))))
 (list "block-edit"))

(provide block-guard blockview-clamp! blockview-first-content blockview-step blockview-command-up blockview-command-down
         blockview-command-edit blockview-content blockview-hi)
