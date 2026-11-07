#lang racket/base
(require racket/list racket/string "pane-width.rkt")
(provide (struct-out pane-grid) make-pane-grid pane-grid-feed! pane-grid-resize! pane-grid-osc52-hook)

(struct pane-grid (columns height rows cursor-row cursor-column style shown top bottom
                   pending-wrap parse-state parse-buffer history alternate saved-main
                   saved-cursor reply)
  #:mutable)

(define blank-cell (cons #\space ""))
(define history-limit 2000)

(define (blank-row columns) (make-vector columns blank-cell))
(define (blank-rows columns height)
  (for/vector ([i (in-range height)]) (blank-row columns)))

(define (make-pane-grid columns height)
  (pane-grid columns height (blank-rows columns height) 0 0 "" #t 0 (sub1 height)
             #f (quote ground) "" (list) #f #f (list 0 0) void))

(define (clamp value low high) (max low (min high value)))

(define (move-cursor! g row column)
  (set-pane-grid-cursor-row! g (clamp row 0 (sub1 (pane-grid-height g))))
  (set-pane-grid-cursor-column! g (clamp column 0 (sub1 (pane-grid-columns g))))
  (set-pane-grid-pending-wrap! g #f))

(define (remember-row! g row)
  (define kept (cons row (pane-grid-history g)))
  (set-pane-grid-history! g (if (> (length kept) history-limit) (take kept history-limit) kept)))

(define (shift-rows-up! g top bottom amount remember?)
  (define rows (pane-grid-rows g))
  (define times (min amount (add1 (- bottom top))))
  (for ([i (in-range times)])
    (when (and remember? (= top 0) (not (pane-grid-alternate g)))
      (remember-row! g (vector-ref rows 0)))
    (for ([r (in-range top bottom)])
      (vector-set! rows r (vector-ref rows (add1 r))))
    (vector-set! rows bottom (blank-row (pane-grid-columns g)))))

(define (shift-rows-down! g top bottom amount)
  (define rows (pane-grid-rows g))
  (define times (min amount (add1 (- bottom top))))
  (for ([i (in-range times)])
    (for ([r (in-range bottom top -1)])
      (vector-set! rows r (vector-ref rows (sub1 r))))
    (vector-set! rows top (blank-row (pane-grid-columns g)))))

(define (scroll-region-up! g amount)
  (shift-rows-up! g (pane-grid-top g) (pane-grid-bottom g) amount #t))

(define (scroll-region-down! g amount)
  (shift-rows-down! g (pane-grid-top g) (pane-grid-bottom g) amount))

(define (line-feed! g)
  (define row (pane-grid-cursor-row g))
  (cond
    [(= row (pane-grid-bottom g)) (scroll-region-up! g 1)]
    [(< row (sub1 (pane-grid-height g))) (set-pane-grid-cursor-row! g (add1 row))]))

(define (reverse-line-feed! g)
  (define row (pane-grid-cursor-row g))
  (cond
    [(= row (pane-grid-top g)) (scroll-region-down! g 1)]
    [(> row 0) (set-pane-grid-cursor-row! g (sub1 row))]))

(define (put-char! g ch)
  (define width (char-columns ch))
  (when (and (> width 0) (<= width (pane-grid-columns g)))
    (when (or (pane-grid-pending-wrap g)
              (> (+ (pane-grid-cursor-column g) width) (pane-grid-columns g)))
      (set-pane-grid-pending-wrap! g #f)
      (set-pane-grid-cursor-column! g 0)
      (line-feed! g))
    (define cells (vector-ref (pane-grid-rows g) (pane-grid-cursor-row g)))
    (define column (pane-grid-cursor-column g))
    (vector-set! cells column (cons ch (pane-grid-style g)))
    (when (= width 2)
      (vector-set! cells (add1 column) (cons #\nul (pane-grid-style g))))
    (define next (+ column width))
    (cond
      [(>= next (pane-grid-columns g))
       (set-pane-grid-cursor-column! g (sub1 (pane-grid-columns g)))
       (set-pane-grid-pending-wrap! g #t)]
      [else (set-pane-grid-cursor-column! g next)])))

(define (erase-cells! g row from to)
  (define cells (vector-ref (pane-grid-rows g) row))
  (for ([c (in-range (max 0 from) (min (pane-grid-columns g) to))])
    (vector-set! cells c blank-cell)))

(define (erase-display! g mode)
  (define row (pane-grid-cursor-row g))
  (define column (pane-grid-cursor-column g))
  (define columns (pane-grid-columns g))
  (define height (pane-grid-height g))
  (case mode
    [(0) (erase-cells! g row column columns)
         (for ([r (in-range (add1 row) height)]) (erase-cells! g r 0 columns))]
    [(1) (for ([r (in-range 0 row)]) (erase-cells! g r 0 columns))
         (erase-cells! g row 0 (add1 column))]
    [else (for ([r (in-range 0 height)]) (erase-cells! g r 0 columns))
          (when (= mode 3) (set-pane-grid-history! g (list)))]))

(define (erase-line! g mode)
  (define row (pane-grid-cursor-row g))
  (define column (pane-grid-cursor-column g))
  (case mode
    [(0) (erase-cells! g row column (pane-grid-columns g))]
    [(1) (erase-cells! g row 0 (add1 column))]
    [else (erase-cells! g row 0 (pane-grid-columns g))]))

(define (insert-lines! g amount)
  (define row (pane-grid-cursor-row g))
  (when (and (>= row (pane-grid-top g)) (<= row (pane-grid-bottom g)))
    (shift-rows-down! g row (pane-grid-bottom g) amount)))

(define (delete-lines! g amount)
  (define row (pane-grid-cursor-row g))
  (when (and (>= row (pane-grid-top g)) (<= row (pane-grid-bottom g)))
    (shift-rows-up! g row (pane-grid-bottom g) amount #f)))

(define (delete-chars! g amount)
  (define cells (vector-ref (pane-grid-rows g) (pane-grid-cursor-row g)))
  (define column (pane-grid-cursor-column g))
  (define columns (pane-grid-columns g))
  (define n (min amount (- columns column)))
  (for ([c (in-range column (- columns n))])
    (vector-set! cells c (vector-ref cells (+ c n))))
  (for ([c (in-range (- columns n) columns)])
    (vector-set! cells c blank-cell)))

(define (insert-chars! g amount)
  (define cells (vector-ref (pane-grid-rows g) (pane-grid-cursor-row g)))
  (define column (pane-grid-cursor-column g))
  (define columns (pane-grid-columns g))
  (define n (min amount (- columns column)))
  (for ([c (in-range (sub1 columns) (sub1 (+ column n)) -1)])
    (vector-set! cells c (vector-ref cells (- c n))))
  (for ([c (in-range column (+ column n))])
    (vector-set! cells c blank-cell)))

(define (apply-sgr! g ps)
  (define first-param (if (null? ps) 0 (or (car ps) 0)))
  (define later (if (null? ps) (list) (cdr ps)))
  (define (sequence-of params)
    (string-append "\u001b["
                   (string-join (map (lambda (p) (if p (number->string p) "")) params) ";")
                   "m"))
  (cond
    [(= first-param 0)
     (set-pane-grid-style! g (if (null? later) "" (sequence-of later)))]
    [else
     (define joined (string-append (pane-grid-style g) (sequence-of ps)))
     (set-pane-grid-style! g (if (> (string-length joined) 240) (sequence-of ps) joined))]))

(define (save-cursor! g)
  (set-pane-grid-saved-cursor! g (list (pane-grid-cursor-row g) (pane-grid-cursor-column g))))

(define (restore-cursor! g)
  (define saved (pane-grid-saved-cursor g))
  (move-cursor! g (car saved) (cadr saved)))

(define (fit-rows rows columns height)
  (define fresh (blank-rows columns height))
  (for ([r (in-range (min height (vector-length rows)))])
    (define old (vector-ref rows r))
    (for ([c (in-range (min columns (vector-length old)))])
      (vector-set! (vector-ref fresh r) c (vector-ref old c))))
  fresh)

(define (enter-alternate! g)
  (unless (pane-grid-alternate g)
    (set-pane-grid-saved-main! g (list (pane-grid-rows g) (pane-grid-cursor-row g) (pane-grid-cursor-column g)))
    (set-pane-grid-rows! g (blank-rows (pane-grid-columns g) (pane-grid-height g)))
    (set-pane-grid-alternate! g #t)))

(define (leave-alternate! g)
  (when (pane-grid-alternate g)
    (define saved (pane-grid-saved-main g))
    (set-pane-grid-rows! g (fit-rows (car saved) (pane-grid-columns g) (pane-grid-height g)))
    (set-pane-grid-alternate! g #f)
    (move-cursor! g (cadr saved) (caddr saved))))

(define (reset-grid! g)
  (set-pane-grid-rows! g (blank-rows (pane-grid-columns g) (pane-grid-height g)))
  (set-pane-grid-alternate! g #f)
  (set-pane-grid-style! g "")
  (set-pane-grid-top! g 0)
  (set-pane-grid-bottom! g (sub1 (pane-grid-height g)))
  (set-pane-grid-shown! g #t)
  (move-cursor! g 0 0))

(define (set-scroll-region! g top bottom)
  (when (and (>= top 0) (< top bottom) (< bottom (pane-grid-height g)))
    (set-pane-grid-top! g top)
    (set-pane-grid-bottom! g bottom))
  (move-cursor! g 0 0))

(define (apply-private-modes! g ps on?)
  (for ([mode (in-list ps)])
    (case mode
      [(25) (set-pane-grid-shown! g on?)]
      [(47 1047 1049) (if on? (enter-alternate! g) (leave-alternate! g))]
      [else (void)])))

(define (csi-final! g buffer final)
  (define lead (if (string=? buffer "") #\nul (string-ref buffer 0)))
  (define private? (char=? lead #\?))
  (define ignored? (or (memv lead (list #\> #\< #\=)) (regexp-match? #rx" " buffer)))
  (define body (if private? (substring buffer 1) buffer))
  (define ps (map string->number (string-split body ";" #:trim? #f)))
  (define (raw index) (or (and (< index (length ps)) (list-ref ps index)) 0))
  (define (amount index) (max 1 (raw index)))
  (define row (pane-grid-cursor-row g))
  (define column (pane-grid-cursor-column g))
  (cond
    [ignored? (void)]
    [private? (when (memv final (list #\h #\l)) (apply-private-modes! g ps (char=? final #\h)))]
    [else
     (case final
       [(#\A) (move-cursor! g (- row (amount 0)) column)]
       [(#\B #\e) (move-cursor! g (+ row (amount 0)) column)]
       [(#\C #\a) (move-cursor! g row (+ column (amount 0)))]
       [(#\D) (move-cursor! g row (- column (amount 0)))]
       [(#\E) (move-cursor! g (+ row (amount 0)) 0)]
       [(#\F) (move-cursor! g (- row (amount 0)) 0)]
       [(#\G) (move-cursor! g row (sub1 (amount 0)))]
       [(#\H #\f) (move-cursor! g (sub1 (amount 0)) (sub1 (amount 1)))]
       [(#\d) (move-cursor! g (sub1 (amount 0)) column)]
       [(#\J) (erase-display! g (raw 0))]
       [(#\K) (erase-line! g (raw 0))]
       [(#\L) (insert-lines! g (amount 0))]
       [(#\M) (delete-lines! g (amount 0))]
       [(#\P) (delete-chars! g (amount 0))]
       [(#\@) (insert-chars! g (amount 0))]
       [(#\X) (erase-cells! g row column (+ column (amount 0)))]
       [(#\S) (scroll-region-up! g (amount 0))]
       [(#\T) (scroll-region-down! g (amount 0))]
       [(#\m) (apply-sgr! g ps)]
       [(#\r) (set-scroll-region! g (sub1 (amount 0))
                                  (sub1 (if (> (raw 1) 0) (raw 1) (pane-grid-height g))))]
       [(#\s) (save-cursor! g)]
       [(#\u) (restore-cursor! g)]
       [(#\n) (when (= (raw 0) 6)
                ((pane-grid-reply g)
                 (string->bytes/utf-8 (format "\u001b[~a;~aR" (add1 row) (add1 column)))))]
       [(#\c) ((pane-grid-reply g) (string->bytes/utf-8 "\u001b[?1;2c"))]
       [else (void)])]))

(define (csi-char! g ch)
  (cond
    [(and (char>=? ch #\space) (char<=? ch #\?))
     (set-pane-grid-parse-buffer! g (string-append (pane-grid-parse-buffer g) (string ch)))]
    [(and (char>=? ch #\@) (char<=? ch #\~))
     (set-pane-grid-parse-state! g (quote ground))
     (csi-final! g (pane-grid-parse-buffer g) ch)]
    [else (set-pane-grid-parse-state! g (quote ground))]))

(define (escape-char! g ch)
  (set-pane-grid-parse-state! g (quote ground))
  (case ch
    [(#\[) (set-pane-grid-parse-state! g (quote csi)) (set-pane-grid-parse-buffer! g "")]
    [(#\] #\P #\_ #\^ #\X) (set-pane-grid-parse-state! g (quote osc)) (set-pane-grid-parse-buffer! g "")]
    [(#\( #\) #\* #\+) (set-pane-grid-parse-state! g (quote charset))]
    [(#\7) (save-cursor! g)]
    [(#\8) (restore-cursor! g)]
    [(#\M) (reverse-line-feed! g)]
    [(#\D) (line-feed! g)]
    [(#\E) (set-pane-grid-cursor-column! g 0) (line-feed! g)]
    [(#\c) (reset-grid! g)]
    [else (void)]))

(define pane-grid-osc52-hook
  (box (lambda (body)
         (write-string (string-append "\u001b]" body "\u0007"))
         (flush-output))))

(define (osc-finish! g)
  (define body (pane-grid-parse-buffer g))
  (set-pane-grid-parse-state! g (quote ground))
  (set-pane-grid-parse-buffer! g "")
  (when (and (> (string-length body) 3) (< (string-length body) 30000) (string=? (substring body 0 3) "52;"))
    ((unbox pane-grid-osc52-hook) body)))

(define (osc-char! g ch)
  (cond
    [(char=? ch #\u07) (osc-finish! g)]
    [(char=? ch #\u1B) (set-pane-grid-parse-state! g (quote osc-escape))]
    [(< (string-length (pane-grid-parse-buffer g)) 30000)
     (set-pane-grid-parse-buffer! g (string-append (pane-grid-parse-buffer g) (string ch)))]))

(define (ground-char! g ch)
  (define row (pane-grid-cursor-row g))
  (define column (pane-grid-cursor-column g))
  (cond
    [(char=? ch #\u1B) (set-pane-grid-parse-state! g (quote escape))]
    [(char=? ch #\return) (set-pane-grid-pending-wrap! g #f) (set-pane-grid-cursor-column! g 0)]
    [(memv ch (list #\newline #\vtab #\page)) (set-pane-grid-pending-wrap! g #f) (line-feed! g)]
    [(char=? ch #\backspace) (move-cursor! g row (sub1 column))]
    [(char=? ch #\tab) (move-cursor! g row (+ column (- 8 (modulo column 8))))]
    [(char<? ch #\space) (void)]
    [else (put-char! g ch)]))

(define (feed-char! g ch)
  (case (pane-grid-parse-state g)
    [(ground) (ground-char! g ch)]
    [(escape) (escape-char! g ch)]
    [(csi) (csi-char! g ch)]
    [(osc) (osc-char! g ch)]
    [(osc-escape) (if (char=? ch #\\) (osc-finish! g) (set-pane-grid-parse-state! g (quote osc)))]
    [(charset) (set-pane-grid-parse-state! g (quote ground))]))

(define (pane-grid-feed! g text)
  (for ([ch (in-string text)]) (feed-char! g ch)))

(define (pane-grid-resize! g columns height)
  (define overflow (max 0 (- (add1 (pane-grid-cursor-row g)) height)))
  (define drop? (and (> overflow 0) (not (pane-grid-alternate g))))
  (define rows (pane-grid-rows g))
  (define trimmed
    (cond
      [drop?
       (for ([r (in-range overflow)]) (remember-row! g (vector-ref rows r)))
       (for/vector ([r (in-range overflow (vector-length rows))]) (vector-ref rows r))]
      [else rows]))
  (when (pane-grid-alternate g)
    (define saved (pane-grid-saved-main g))
    (set-pane-grid-saved-main! g (list (fit-rows (car saved) columns height) (cadr saved) (caddr saved))))
  (set-pane-grid-rows! g (fit-rows trimmed columns height))
  (set-pane-grid-columns! g columns)
  (set-pane-grid-height! g height)
  (set-pane-grid-top! g 0)
  (set-pane-grid-bottom! g (sub1 height))
  (move-cursor! g (- (pane-grid-cursor-row g) (if drop? overflow 0)) (pane-grid-cursor-column g)))
