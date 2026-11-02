#lang racket/base
;; clip.rkt: copy, cut and paste with a ring of copies. Copy takes the text of every selection (several
;; selections make several pieces); with no selection it takes the block under the point of a page, or the line.
;; Paste gives one piece to each cursor when the counts match, the one piece to every cursor when there is one,
;; and all pieces joined by newlines otherwise; a cursor that selects something has it replaced. A copy also goes
;; to the terminal clipboard with the OSC 52 escape. Loaded on first use through the stubs at the end of bar.rkt.
;; Nothing here runs while typing.

(require "../commands/commands.rkt"
         "../notation/document.rkt"
         "../notation/host.rkt"
         (only-in racket/string string-join)
         (only-in net/base64 base64-encode)
         (only-in "blocks/blockview.rkt" blockview-inside blockview-drawn)
         (only-in "bar.rkt" clip-table)
         (only-in "notify.rkt" notify!))

;; cp-ring keeps the copies, newest first; each copy is a list of pieces of text.
(define cp-ring (list))

;; cp-first answers the first n items of a list.
(define (cp-first n l) (if (or (<= n 0) (null? l)) (list) (cons (car l) (cp-first (sub1 n) (cdr l)))))

;; cp-bytes answers the text of the session as bytes; every offset is a byte offset.
(define (cp-bytes session) (string->bytes/utf-8 (session-text session)))

;; cp-slice answers the text between two byte offsets.
(define (cp-slice bs lo hi)
  (bytes->string/utf-8 (subbytes bs (min lo (bytes-length bs)) (min hi (bytes-length bs))) #\?))

;; cp-blen answers the length of a text in bytes.
(define (cp-blen s) (bytes-length (string->bytes/utf-8 s)))

;; cp-items answers every cursor as a vector of its head, its anchor and whether it is the main one, from the
;; first place to the last.
(define (cp-items session)
  (let* ([mine? (equal? (unbox multi-file) (session-file session))]
         [main (vector (the-point session) (and mine? (unbox main-anchor)) #t)]
         [more (if mine? (map (lambda (c) (vector (car c) (cdr c) #f)) (unbox extra-cursors)) (list))])
    (sort (cons main more) < #:key (lambda (c) (vector-ref c 0)))))

;; cp-range answers the range a cursor selects as (low . high); the two are equal when it selects nothing.
(define (cp-range c)
  (let ([h (vector-ref c 0)] [a (vector-ref c 1)])
    (if (and a (not (= a h))) (cons (min a h) (max a h)) (cons h h))))

;; cp-selected answers the ranges that hold something, from the first place to the last.
(define (cp-selected session)
  (filter (lambda (r) (< (car r) (cdr r))) (map cp-range (cp-items session))))

;; cp-line-bounds answers the start and the end of the line an offset is on.
(define (cp-line-bounds bs i)
  (let* ([n (bytes-length bs)]
         [p (min i n)]
         [ls (let loop ([j p]) (if (or (<= j 0) (= (bytes-ref bs (sub1 j)) 10)) j (loop (sub1 j))))]
         [le (let loop ([j p]) (if (or (>= j n) (= (bytes-ref bs j) 10)) j (loop (add1 j))))])
    (cons ls le)))

;; cp-fallback answers the text copied when nothing is selected: the block under the point of a page, or the line.
(define (cp-fallback session bs)
  (let* ([got (page-of (session-file session) (session-journal session))]
         [b (and (page? got) (blockview-inside (blockview-drawn (page-blocks got)) (the-point session)))])
    (if b
        (cp-slice bs (block-start b) (block-end b))
        (let ([lb (cp-line-bounds bs (the-point session))])
          (cp-slice bs (car lb) (cdr lb))))))

;; cp-pieces answers the pieces a copy takes.
(define (cp-pieces session)
  (let* ([bs (cp-bytes session)] [rs (cp-selected session)])
    (if (null? rs)
        (list (cp-fallback session bs))
        (map (lambda (r) (cp-slice bs (car r) (cdr r))) rs))))

;; cp-keep! puts a copy at the front of the ring.
(define (cp-keep! pieces) (set! cp-ring (cp-first 50 (cons pieces cp-ring))))

;; cp-osc52! sends a copy to the terminal clipboard; a terminal that does not know the escape ignores it.
(define (cp-osc52! pieces)
  (let ([bs (string->bytes/utf-8 (string-join pieces "\n"))])
    (when (< (bytes-length bs) 60000)
      (write-string (string-append "\u001b]52;c;" (bytes->string/latin-1 (base64-encode bs #"")) "\u0007"))
      (flush-output))))

;; cp-said answers the words for a number of pieces.
(define (cp-said n) (format "~a piece~a" n (if (= n 1) "" "s")))

;; cp-copy copies the selections, or the block or line at the point.
(define (cp-copy session)
  (let ([pieces (cp-pieces session)])
    (cond [(andmap (lambda (p) (string=? p "")) pieces)
           (notify! "info" "nothing to copy")
           (cons #t "nothing")]
          [else
           (cp-keep! pieces)
           (cp-osc52! pieces)
           (notify! "info" (string-append "copied " (cp-said (length pieces))))
           (cons #t "copied")])))

;; cp-replace! replaces the range of every cursor by a text, from the last cursor to the first so no offset moves
;; under one still to be done, and puts every cursor after its text, with no selection left.
(define (cp-replace! session its texts)
  (let ([ranged (for/list ([c (in-list its)] [t (in-list texts)])
                  (let ([r (cp-range c)])
                    (vector (car r) (cdr r) (vector-ref c 2) t)))])
    (for ([x (in-list (reverse ranged))])
      (let ([lo (vector-ref x 0)] [hi (vector-ref x 1)] [t (vector-ref x 3)])
        (when (> hi lo)
          (ask session "delete-at" (hasheq (quote at) (number->string lo) (quote count) (number->string (- hi lo)))))
        (when (> (string-length t) 0)
          (ask session "insert-at" (hasheq (quote at) (number->string lo) (quote text) t)))))
    (let loop ([l ranged] [shift 0] [main 0] [others (list)])
      (cond
        [(null? l)
         (move-to session main)
         (set-box! main-anchor #f)
         (set-box! extra-cursors (map (lambda (h) (cons h #f)) (reverse others)))
         (set-box! multi-file (session-file session))]
        [else
         (let* ([x (car l)] [lo (vector-ref x 0)] [hi (vector-ref x 1)] [t (vector-ref x 3)]
                [head (+ lo (cp-blen t) shift)])
           (loop (cdr l)
                 (+ shift (- (cp-blen t) (- hi lo)))
                 (if (vector-ref x 2) head main)
                 (if (vector-ref x 2) others (cons head others))))]))))

;; cp-cut copies the selections and takes them out; it needs a selection.
(define (cp-cut session)
  (let ([rs (cp-selected session)])
    (cond
      [(null? rs)
       (notify! "info" "select something first: space v")
       (cons #t "nothing")]
      [else
       (let* ([bs (cp-bytes session)]
              [pieces (map (lambda (r) (cp-slice bs (car r) (cdr r))) rs)]
              [its (cp-items session)])
         (cp-keep! pieces)
         (cp-osc52! pieces)
         (cp-replace! session its (map (lambda (c) "") its))
         (notify! "info" (string-append "cut " (cp-said (length pieces))))
         (cons #t "cut"))])))

;; cp-paste puts the newest copy at every cursor, replacing what a cursor selects.
(define (cp-paste session)
  (cond
    [(null? cp-ring)
     (notify! "info" "nothing copied yet")
     (cons #t "nothing")]
    [else
     (let* ([pieces (car cp-ring)]
            [its (cp-items session)]
            [k (length its)]
            [m (length pieces)]
            [texts (cond [(= m k) pieces]
                         [(= m 1) (for/list ([i (in-range k)]) (car pieces))]
                         [else (let ([all (string-join pieces "\n")]) (for/list ([i (in-range k)]) all))])])
       (cp-replace! session its texts)
       (notify! "info" (format "pasted at ~a cursor~a" k (if (= k 1) "" "s")))
       (cons #t "pasted"))]))

;; cp-reg! adds one command to the table of this module.
(define (cp-reg! name f)
  (hash-set! clip-table name (lambda (session words) (f session))))

;; The commands, added when this module is loaded.
(cp-reg! "copy" cp-copy)
(cp-reg! "cut" cp-cut)
(cp-reg! "paste" cp-paste)
