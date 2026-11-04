#lang racket/base

(require "../text/text-motion.rkt"
         "../../commands/commands.rkt"
         "../../bridge/document.rkt"
         "../../bridge/host.rkt"
         (only-in "../blocks/blockview.rkt" blockview-kind-match? blockview-inside blockview-drawn)
         (only-in "../bar/bar.rkt" multi-table)
         "multi-notes.rkt"
         (only-in "multi-draw.rkt" multi-lit multi-text-overlay))



(define (multi-bytes session) (string->bytes/utf-8 (session-text session)))

(define (multi-begin! session)
  (unless (equal? (unbox multi-file) (session-file session))
    (multi-clear!))
  (set-box! multi-file (session-file session)))

(define (multi-cursors session)
  (cons (vector (the-point session) (unbox main-anchor) #t)
        (map (lambda (c) (vector (car c) (cdr c) #f)) (unbox extra-cursors))))

(define (multi-total) (add1 (length (unbox extra-cursors))))

(define (multi-store! session cs)
  (let* ([sorted (sort cs < #:key (lambda (c) (vector-ref c 0)))]
         [uniq (let loop ([l sorted] [out (list)])
                 (cond [(null? l) (reverse out)]
                       [(and (pair? out) (= (vector-ref (car out) 0) (vector-ref (car l) 0)))
                        (loop (cdr l) (if (vector-ref (car l) 2) (cons (car l) (cdr out)) out))]
                       [else (loop (cdr l) (cons (car l) out))]))]
         [main (or (for/first ([c (in-list uniq)] #:when (vector-ref c 2)) c) (car uniq))])
    (move-to session (vector-ref main 0))
    (set-box! main-anchor (vector-ref main 1))
    (set-box! extra-cursors
              (for/list ([c (in-list uniq)] #:unless (eq? c main))
                (cons (vector-ref c 0) (vector-ref c 1))))
    (set-box! multi-file (session-file session))))

(define (multi-blocks session)
  (let ([got (page-of (session-file session) (session-journal session))])
    (and (page? got)
         (sort (filter blockview-kind-match? (blockview-drawn (page-blocks got))) < #:key block-start))))

(define (multi-add-line session step)
  (multi-begin! session)
  (let* ([bs (multi-bytes session)]
         [cs (multi-cursors session)]
         [heads (map (lambda (c) (vector-ref c 0)) cs)]
         [edge (if (> step 0) (apply max heads) (apply min heads))]
         [new (if (> step 0) (multi-down bs edge) (multi-up bs edge))])
    (cond [(= new edge) (multi-note-no-line) (cons #t "none")]
          [else (multi-store! session (cons (vector new #f #f) cs))
                (multi-note-cursors (multi-total))
                (cons #t "added")])))

(define (multi-add-block session forward?)
  (multi-begin! session)
  (let ([blocks (multi-blocks session)])
    (cond
      [(not blocks) (multi-add-line session (if forward? 1 -1))]
      [else
       (let* ([cs (multi-cursors session)]
              [heads (map (lambda (c) (vector-ref c 0)) cs)]
              [b (if forward?
                     (let ([m (apply max heads)])
                       (for/first ([x (in-list blocks)] #:when (> (block-start x) m)) x))
                     (let ([m (apply min heads)])
                       (for/first ([x (in-list (reverse blocks))] #:when (< (block-start x) m)) x)))])
         (cond [b (multi-store! session (cons (vector (block-start b) #f #f) cs))
                  (multi-note-cursors (multi-total))
                  (cons #t "added")]
               [else (multi-note-no-block) (cons #t "none")]))])))

(define (multi-needle session bs)
  (let* ([n (bytes-length bs)]
         [h (min (the-point session) n)]
         [a (and (unbox main-anchor) (min (unbox main-anchor) n))])
    (cond
      [(and a (not (= a h))) (subbytes bs (min a h) (max a h))]
      [else
       (let ([w (multi-word-at bs h)])
         (and (< (car w) (cdr w))
              (begin (set-box! main-anchor (car w))
                     (move-to session (cdr w))
                     (subbytes bs (car w) (cdr w)))))])))

(define (multi-add-match session)
  (multi-begin! session)
  (let* ([bs (multi-bytes session)] [needle (multi-needle session bs)])
    (cond
      [(not needle) (multi-note-no-word) (cons #t "none")]
      [else
       (let* ([cs (multi-cursors session)]
              [from (apply max (map (lambda (c) (max (vector-ref c 0) (or (vector-ref c 1) 0))) cs))]
              [m (regexp-match-positions (byte-regexp (regexp-quote needle)) bs (min from (bytes-length bs)))])
         (cond [m (multi-store! session (cons (vector (cdar m) (caar m) #f) cs))
                  (multi-note-cursors (multi-total))
                  (cons #t "added")]
               [else (multi-note-no-more-matches) (cons #t "none")]))])))

(define (multi-add-all session)
  (multi-begin! session)
  (let* ([bs (multi-bytes session)] [needle (multi-needle session bs)])
    (cond
      [(not needle) (multi-note-no-word) (cons #t "none")]
      [else
       (let* ([ms (regexp-match-positions* (byte-regexp (regexp-quote needle)) bs)]
              [cs (multi-cursors session)]
              [have (map (lambda (c) (vector-ref c 0)) cs)]
              [added (for/list ([m (in-list ms)] #:unless (member (cdr m) have))
                       (vector (cdr m) (car m) #f))])
         (multi-store! session (append cs added))
         (multi-note-cursors (multi-total))
         (cons #t "added"))])))

(define (multi-drop session)
  (let ([ex (unbox extra-cursors)])
    (cond [(null? ex) (multi-note-only-main) (cons #t "none")]
          [else (set-box! extra-cursors (reverse (cdr (reverse ex))))
                (multi-note-cursors (multi-total))
                (cons #t "dropped")])))

(define (multi-clear session)
  (multi-clear!)
  (multi-note-cleared)
  (cons #t "cleared"))

(define (multi-cursor-mode session)
  (multi-begin! session)
  (set-layer! session "cursor")
  (multi-note-cursor-help)
  (cons #t "layer: cursor"))

(define (multi-cursor-leave session)
  (set-layer! session "visual")
  (cons #t "layer: visual"))

(define (multi-select-mode session)
  (multi-begin! session)
  (multi-store! session
             (for/list ([c (in-list (multi-cursors session))])
               (vector (vector-ref c 0) (or (vector-ref c 1) (vector-ref c 0)) (vector-ref c 2))))
  (set-box! multi-raw-view #f)
  (set-layer! session "select")
  (multi-note-select-help)
  (cons #t "layer: select"))

(define (multi-extend session f)
  (multi-begin! session)
  (let ([bs (multi-bytes session)])
    (multi-store! session
               (for/list ([c (in-list (multi-cursors session))])
                 (let ([h (vector-ref c 0)] [a (vector-ref c 1)])
                   (vector (f bs h) (or a h) (vector-ref c 2)))))
    (set-box! multi-raw-view #t)
    (cons #t "selected")))

(define (multi-block-cursor blocks n c forward?)
  (let* ([h (vector-ref c 0)] [a (vector-ref c 1)] [main? (vector-ref c 2)]
         [lo (if a (min a h) h)] [hi (if a (max a h) h)]
         [sel? (and a (not (= a h)))])
    (cond
      [(not sel?)
       (let ([b (or (blockview-inside blocks h)
                    (if forward?
                        (for/first ([x (in-list blocks)] #:when (>= (block-start x) h)) x)
                        (for/first ([x (in-list (reverse blocks))] #:when (<= (block-end x) h)) x)))])
         (if b
             (let ([s (block-start b)] [e (min n (block-end b))])
               (if forward? (vector e s main?) (vector s e main?)))
             c))]
      [forward?
       (let ([b (for/first ([x (in-list blocks)] #:when (>= (block-start x) hi)) x)])
         (if b (vector (min n (block-end b)) lo main?) c))]
      [else
       (let ([b (for/first ([x (in-list (reverse blocks))] #:when (<= (block-end x) lo)) x)])
         (if b (vector (block-start b) hi main?) c))])))

(define (multi-block-step session forward?)
  (multi-begin! session)
  (let ([blocks (multi-blocks session)])
    (cond
      [(not blocks) (multi-extend session (if forward? multi-down multi-up))]
      [else
       (let ([n (bytes-length (multi-bytes session))])
         (multi-store! session
                    (for/list ([c (in-list (multi-cursors session))])
                      (multi-block-cursor blocks n c forward?)))
         (set-box! multi-raw-view #f)
         (cons #t "selected"))])))

(define (multi-cancel session)
  (set-box! main-anchor #f)
  (set-box! extra-cursors (map (lambda (c) (cons (car c) #f)) (unbox extra-cursors)))
  (set-box! multi-raw-view #f)
  (set-layer! session "visual")
  (cons #t "selection dropped"))

(define (multi-cut-range! session lo hi)
  (when (> hi lo)
    (ask session "delete-at" (hasheq (quote at) (number->string lo) (quote count) (number->string (- hi lo))))))

(define (multi-edit-text name orig session words)
  (let* ([cs (sort (multi-cursors session) > #:key (lambda (c) (vector-ref c 0)))]
         [res (for/list ([c (in-list cs)])
                (let* ([h (vector-ref c 0)] [a (vector-ref c 1)]
                       [sel? (and a (not (= a h)))]
                       [lo (if sel? (min a h) h)]
                       [hi (if sel? (max a h) h)])
                  (when sel? (multi-cut-range! session lo hi))
                  (move-to session lo)
                  (unless (and sel? (string=? name "delete")) (orig session words))
                  (let ([p (the-point session)])
                    (vector p (- p hi) (vector-ref c 2)))))])
    (let loop ([asc (reverse res)] [shift 0] [out (list)])
      (if (null? asc)
          (multi-store! session out)
          (let* ([r (car asc)] [p (+ (vector-ref r 0) shift)])
            (loop (cdr asc) (+ shift (vector-ref r 1)) (cons (vector p #f (vector-ref r 2)) out)))))
    (cons #t "edited")))

(define (multi-move-all name session)
  (let* ([bs (multi-bytes session)]
         [f (cond [(string=? name "move-left") multi-left]
                  [(string=? name "move-right") multi-right]
                  [(string=? name "move-up") multi-up]
                  [else multi-down])])
    (multi-store! session
               (for/list ([c (in-list (multi-cursors session))])
                 (vector (f bs (vector-ref c 0)) (vector-ref c 1) (vector-ref c 2))))
    (cons #t "moved")))

(define (multi-edit name orig session words)
  (if (member name (list "type" "delete"))
      (multi-edit-text name orig session words)
      (multi-move-all name session)))

(define (multi-reg! name f)
  (hash-set! multi-table name (lambda (session words) (f session))))

(multi-reg! "cursor-mode" multi-cursor-mode)
(multi-reg! "cur-leave" multi-cursor-leave)
(multi-reg! "cur-below" (lambda (s) (multi-add-line s 1)))
(multi-reg! "cur-above" (lambda (s) (multi-add-line s -1)))
(multi-reg! "cur-next-block" (lambda (s) (multi-add-block s #t)))
(multi-reg! "cur-prev-block" (lambda (s) (multi-add-block s #f)))
(multi-reg! "cur-next-match" multi-add-match)
(multi-reg! "cur-all-matches" multi-add-all)
(multi-reg! "cur-drop" multi-drop)
(multi-reg! "cur-clear" multi-clear)
(multi-reg! "select-mode" multi-select-mode)
(multi-reg! "sel-left" (lambda (s) (multi-extend s multi-left)))
(multi-reg! "sel-right" (lambda (s) (multi-extend s multi-right)))
(multi-reg! "sel-up" (lambda (s) (multi-extend s multi-up)))
(multi-reg! "sel-down" (lambda (s) (multi-extend s multi-down)))
(multi-reg! "sel-word" (lambda (s) (multi-extend s multi-word-fwd)))
(multi-reg! "sel-word-back" (lambda (s) (multi-extend s multi-word-back)))
(multi-reg! "sel-block-forward" (lambda (s) (multi-block-step s #t)))
(multi-reg! "sel-block-back" (lambda (s) (multi-block-step s #f)))
(multi-reg! "sel-next-match" multi-add-match)
(multi-reg! "sel-all-matches" multi-add-all)
(multi-reg! "sel-drop" multi-drop)
(multi-reg! "sel-cancel" multi-cancel)
(set-box! multi-edit-hook multi-edit)
(set-box! multi-lit-hook multi-lit)
(set-box! multi-text-hook multi-text-overlay)
