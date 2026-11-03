#lang racket/base

(require "../../commands/commands.rkt"
         "../../bridge/document.rkt"
         "../../bridge/host.rkt"
         (only-in racket/string string-join)
         (only-in net/base64 base64-encode)
         (only-in "../blocks/blockview.rkt" blockview-inside blockview-drawn)
         (only-in "../bar/bar.rkt" clip-table)
         "clip-notes.rkt")

(define cp-ring (list))

(define (cp-first n l) (if (or (<= n 0) (null? l)) (list) (cons (car l) (cp-first (sub1 n) (cdr l)))))

(define (cp-bytes session) (string->bytes/utf-8 (session-text session)))

(define (cp-slice bs lo hi)
  (bytes->string/utf-8 (subbytes bs (min lo (bytes-length bs)) (min hi (bytes-length bs))) #\?))

(define (cp-blen s) (bytes-length (string->bytes/utf-8 s)))

(define (cp-items session)
  (let* ([mine? (equal? (unbox multi-file) (session-file session))]
         [main (vector (the-point session) (and mine? (unbox main-anchor)) #t)]
         [more (if mine? (map (lambda (c) (vector (car c) (cdr c) #f)) (unbox extra-cursors)) (list))])
    (sort (cons main more) < #:key (lambda (c) (vector-ref c 0)))))

(define (cp-range c)
  (let ([h (vector-ref c 0)] [a (vector-ref c 1)])
    (if (and a (not (= a h))) (cons (min a h) (max a h)) (cons h h))))

(define (cp-selected session)
  (filter (lambda (r) (< (car r) (cdr r))) (map cp-range (cp-items session))))

(define (cp-line-bounds bs i)
  (let* ([n (bytes-length bs)]
         [p (min i n)]
         [ls (let loop ([j p]) (if (or (<= j 0) (= (bytes-ref bs (sub1 j)) 10)) j (loop (sub1 j))))]
         [le (let loop ([j p]) (if (or (>= j n) (= (bytes-ref bs j) 10)) j (loop (add1 j))))])
    (cons ls le)))

(define (cp-fallback session bs)
  (let* ([got (page-of (session-file session) (session-journal session))]
         [b (and (page? got) (blockview-inside (blockview-drawn (page-blocks got)) (the-point session)))])
    (if b
        (cp-slice bs (block-start b) (block-end b))
        (let ([lb (cp-line-bounds bs (the-point session))])
          (cp-slice bs (car lb) (cdr lb))))))

(define (cp-pieces session)
  (let* ([bs (cp-bytes session)] [rs (cp-selected session)])
    (if (null? rs)
        (list (cp-fallback session bs))
        (map (lambda (r) (cp-slice bs (car r) (cdr r))) rs))))

(define (cp-keep! pieces) (set! cp-ring (cp-first 50 (cons pieces cp-ring))))

(define (cp-osc52! pieces)
  (let ([bs (string->bytes/utf-8 (string-join pieces "\n"))])
    (when (< (bytes-length bs) 60000)
      (write-string (string-append "\u001b]52;c;" (bytes->string/latin-1 (base64-encode bs #"")) "\u0007"))
      (flush-output))))



(define (cp-copy session)
  (let ([pieces (cp-pieces session)])
    (cond [(andmap (lambda (p) (string=? p "")) pieces)
           (clip-note-nothing-to-copy)
           (cons #t "nothing")]
          [else
           (cp-keep! pieces)
           (cp-osc52! pieces)
           (clip-note-copied (length pieces))
           (cons #t "copied")])))

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

(define (cp-cut session)
  (let ([rs (cp-selected session)])
    (cond
      [(null? rs)
       (clip-note-select-first)
       (cons #t "nothing")]
      [else
       (let* ([bs (cp-bytes session)]
              [pieces (map (lambda (r) (cp-slice bs (car r) (cdr r))) rs)]
              [its (cp-items session)])
         (cp-keep! pieces)
         (cp-osc52! pieces)
         (cp-replace! session its (map (lambda (c) "") its))
         (clip-note-cut (length pieces))
         (cons #t "cut"))])))

(define (cp-paste session)
  (cond
    [(null? cp-ring)
     (clip-note-nothing-copied)
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
       (clip-note-pasted k)
       (cons #t "pasted"))]))

(define (cp-reg! name f)
  (hash-set! clip-table name (lambda (session words) (f session))))

(cp-reg! "copy" cp-copy)
(cp-reg! "cut" cp-cut)
(cp-reg! "paste" cp-paste)
