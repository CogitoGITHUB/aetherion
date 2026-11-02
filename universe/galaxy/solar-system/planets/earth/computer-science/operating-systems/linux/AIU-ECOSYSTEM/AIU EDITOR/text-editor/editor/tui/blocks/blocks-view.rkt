#lang racket/base
;; One job: draw the block view overlays (lit block, floating block, edit box) over the live screen.

(require racket/list racket/string "../../commands/commands.rkt" "../../machine/terminal.rkt" "../../notation/document.rkt" "../../notation/host.rkt" "../float/pins.rkt" "blocks-kind.rkt" "blockview.rkt" "blocks-text.rkt")

(provide block-overlay)

;; blockview-view-overlay answers the drawing with the block at the point lit, the
;; point and the first line to show, or nothing when no block can be lit.
(define (blockview-view-overlay-base session raw width height got)
  (define lines (string-split (drawn-view session raw width) "\n" #:trim? #f))
  (define ranges (blockview-ranges got lines))
  (define target (blockview-target (page-blocks got) (the-point session) ranges))
  (define range (and target (hash-ref ranges (block-start target))))
  (and range
       (list (string-join
              (for/list ([l (in-list lines)] [i (in-naturals)])
                (let ([lit? (or (<= (car range) i (cdr range)) (ormap (lambda (r) (<= (car r) i (cdr r))) (blockview-multi-lit session got ranges)))]) (if (and (getenv "AIU_FOCUS_COLOURS") (not lit?)) (blockview-kind-line got target range i) (string-append (if lit? "\u001b[97m" "\u001b[90m") (blockview-plain l) "\u001b[0m"))))
              "\n")
             (the-point session)
             (blockview-place (add1 (car range)) (add1 (cdr range)) (max 1 (- height 1))))))

;; blockview-view-overlay answers the floating drawing with every shown pin copied onto its screen edge when its block has scrolled out of the window.
(define (blockview-view-overlay session raw width height got)
  (define lines (string-split (drawn-view session raw width) "\n" #:trim? #f))
  (define ranges (blockview-ranges got lines))
  (define bl (page-blocks got))
  (define target (blockview-target bl (the-point session) ranges))
  (set-box! cur-start (and target (block-start target)))
  (when (pair? bl) (set-box! first-start (block-start (car bl))))
  (define r (blockview-view-overlay-float session raw width height got))
  (define focus? (and (getenv "AIU_FOCUS_COLOURS") #t))
  (cond
    [(and r (pair? (pins-now)))
     (define ls0 (list->vector (string-split (car r) "\n" #:trim? #f)))
     (define lv (list->vector lines))
     (define top (caddr r))
     (define visible (max 1 (- height 1)))
     (define lo (- top 1))
     (define hi (+ lo visible -1))
     (define v (make-vector (max (vector-length ls0) (+ hi 1)) ""))
     (for ([i (in-range (vector-length ls0))]) (vector-set! v i (vector-ref ls0 i)))
     (let loop ([all (pins-now)] [i 0] [to 0] [bo 0])
       (unless (null? all)
         (define p (car all))
         (define rng (hash-ref ranges (car p) #f))
         (define shown? (and rng (not (caddr p)) (or (not focus?) (cadddr p))))
         (define k (if rng (+ (- (cdr rng) (car rng)) 1) 0))
         (define inside? (and rng (>= (car rng) lo) (<= (cdr rng) hi)))
         (cond
           [(and shown? (not inside?) (<= (+ to bo k) visible))
            (define top? (equal? (cadr p) "top"))
            (define start (if top? (+ lo to) (+ (- hi bo k) 1)))
            (define colour (if (= i (unbox pin-sel)) "\u001b[97m" "\u001b[90m"))
            (for ([j (in-range k)])
              (define idx (+ (car rng) j))
              (vector-set! v (+ start j) (if (< idx (vector-length lv)) (string-append colour (blockview-plain (vector-ref lv idx)) "\u001b[0m") "")))
            (loop (cdr all) (add1 i) (if top? (+ to k) to) (if top? bo (+ bo k)))]
           [else (loop (cdr all) (add1 i) to bo)])))
     (list (string-join (vector->list v) "\n") (cadr r) top)]
    [else r]))

;; blockview-view-overlay answers the base drawing, and after a scroll key it copies the lit block onto the bottom edge of the window when the block is below it, or the top edge when it is above it.
(define (blockview-view-overlay-float session raw width height got)
  (define r (blockview-view-overlay-base session raw width height got))
  (define rng (unbox lit-range))
  (cond
    [(and r (unbox free-block) rng)
     (define ls (list->vector (string-split (car r) "\n" #:trim? #f)))
     (define n (vector-length ls))
     (define visible (max 1 (- height 1)))
     (define top (max 1 (min (caddr r) (max 1 n))))
     (set-box! top-line top)
     (define from (car rng))
     (define to (cdr rng))
     (define k (+ (- to from) 1))
     (define v (make-vector (max n (+ top visible)) ""))
     (for ([i (in-range n)]) (vector-set! v i (vector-ref ls i)))
     (define start
       (cond [(>= k visible) #f]
             [(< to top) (- top 1)]
             [(> from (+ top visible -1)) (+ (- top 1) (- visible k))]
             [else #f]))
     (when start
       (for ([j (in-range k)])
         (vector-set! v (+ start j) (if (< (+ (- from 1) j) n) (vector-ref ls (+ (- from 1) j)) ""))))
     (list (string-join (vector->list v) "\n") (cadr r) top)]
    [else r]))

;; blockview-edit-overlay answers the drawing with the block being edited shown as raw
;; text, with its start and end lines, and every other block drawn. The raw lines
;; sit behind the left edge of the box that holds the block, and a line wider than
;; the screen is cut at a space with the edge drawn on every part, so the boxes
;; around stay in place. It answers the point and the first line to show, or
;; nothing when the block can no longer be found.
(define (blockview-edit-overlay session raw width height got)
  (define start (unbox edit-start))
  (define b
    (for/first ([x (in-list (page-blocks got))] #:when (= (block-start x) start))
      x))
  (define lines (string-split (drawn-view session raw width) "\n" #:trim? #f))
  (define range (and b (hash-ref (blockview-ranges got lines) start #f)))
  (cond
    [(not range)
     (set-box! edit-start #f)
     #f]
    [else
     (define bs (string->bytes/utf-8 raw))
     (define end (min (block-end b) (bytes-length bs)))
     (define edge (blockview-prefix (block-depth b)))
     (define before (take lines (car range)))
     (define after (drop lines (min (length lines) (add1 (cdr range)))))
     (define wb (max 12 (- (string-length (blockview-plain (list-ref lines (car range)))) (* 4 (block-depth b)))))
     (define tail (apply string-append (for/list ([i (in-range (block-depth b))]) " │")))
     (define cw wb)
     (define rel (max 0 (min (- (the-point session) start) (- end start))))
     (define text-lines
       (string-split (bytes->string/utf-8 (subbytes bs start end) #\?) "\n" #:trim? #f))
     (define k
       (min (sub1 (length text-lines))
            (for/sum ([c (in-bytes (subbytes bs start (+ start rel)))]) (if (= c 10) 1 0))))
     (define line-start
       (let loop ([i (+ start rel)])
         (if (or (<= i start) (= (bytes-ref bs (sub1 i)) 10)) (max i start) (loop (sub1 i)))))
     (define col
       (string-length (bytes->string/utf-8 (subbytes bs line-start (+ start rel)) #\?)))
     (define parts (for/list ([l (in-list text-lines)]) (blockview-chunks l cw)))
     (define shown
       (for*/list ([(l ps) (in-parallel text-lines parts)] [p (in-list ps)])
         (string-append edge (blockview-pad (substring l (car p) (cdr p)) cw) tail)))
     (define mine (list-ref parts k))
     (define ci
       (or (for/first ([p (in-list mine)] [n (in-naturals)]
                       #:when (or (< col (cdr p)) (eq? p (last mine))))
             n)
           0))
     (define before-count
       (for/sum ([ps (in-list parts)] [n (in-range k)]) (length ps)))
     (define idx (+ before-count ci))
     (define cp (list-ref mine ci))
     (define cur (list-ref text-lines k))
     (define head-bytes
       (for/sum ([l (in-list before)]) (add1 (bytes-length (string->bytes/utf-8 l)))))
     (define pre-bytes
       (for/sum ([x (in-list (take shown idx))])
         (add1 (bytes-length (string->bytes/utf-8 x)))))
     (define at-bytes
       (+ (bytes-length (string->bytes/utf-8 edge))
          (bytes-length
           (string->bytes/utf-8
            (substring cur (car cp) (max (car cp) (min col (string-length cur))))))))
     (define row (+ (length before) 1 idx))
     (list (string-join (append before shown after) "\n")
           (+ head-bytes pre-bytes at-bytes)
           (blockview-follow row row (max 1 (- height 1))))]))

;; blockview-focus-pad puts the edited block in the middle of the window: blank lines are added above it when it sits near the page top, and the cursor offset moves by the bytes added. A block taller than the window is left alone.
(define (blockview-focus-pad range height res)
  (define visible (max 1 (- height 1)))
  (define from (+ (car range) 1))
  (define h (+ (- (cdr range) (car range)) 1))
  (define want (quotient (- visible h) 2))
  (cond
    [(>= h visible) res]
    [else
     (define pad (max 0 (- want (- from 1))))
     (list (string-append (make-string pad #\newline) (car res))
           (+ (cadr res) pad)
           (max 1 (- from want)))]))
;; blockview-focus-top answers the first line to show for an edited block in focus mode: the block sits in the middle of the window like in the visual view, and a block taller than the window keeps the old first line so the cursor stays on screen.
(define (blockview-focus-top r range height)
  (define visible (max 1 (- height 1)))
  (define from (+ (car range) 1))
  (define to (+ (cdr range) 1))
  (if (>= (- to from) visible)
      (caddr r)
      (max 1 (- (quotient (+ from to) 2) (quotient visible 2)))))
;; block-overlay answers what the live screen draws for a page: the text, the
;; point and the first line, or nothing when the plain screen should be used.
(define (block-overlay session raw width height)
  (define r0 (block-overlay-base session raw width height))
  (define pg (and (not r0) (getenv "AIU_FOCUS_COLOURS") (string=? (the-layer session) "write") (page-of (session-file session) (session-journal session))))
  (define r (or r0 (and pg (page? pg) (blockview-view-overlay session raw width height pg))))
  (define got (and r (getenv "AIU_FOCUS_COLOURS") (string=? (the-layer session) "write") (unbox edit-start) (page-of (session-file session) (session-journal session))))
  (cond
    [(and got (page? got))
     (define lines (string-split (drawn-view session raw width) "\n" #:trim? #f))
     (define range (hash-ref (blockview-ranges got lines) (unbox edit-start) #f))
     (cond
       [range
        (define out (string-split (car r) "\n" #:trim? #f))
        (define nb (car range))
        (define na (max 0 (- (length lines) (cdr range) 1)))
        (define total (length out))
        (define lost (for/sum ([l (in-list out)] [i (in-range nb)]) (bytes-length (string->bytes/utf-8 l))))
        (blockview-focus-pad range height (list (string-join (for/list ([l (in-list out)] [i (in-naturals)]) (if (or (< i nb) (>= i (- total na))) "" l)) "\n")
              (- (cadr r) lost)
              (blockview-focus-top r range height)))]
       [else r])]
    [else r]))

;; block-overlay-base answers the live drawing of a page without the focus blanking of the lines around an edited block.
(define (block-overlay-base session raw width height)
  (define got (page-of (session-file session) (session-journal session)))
  (define writing? (string=? (the-layer session) "write"))
  (unless writing? (set-box! edit-start #f) (set-box! edit-mode "raw"))
  (cond
    [(not (page? got))
     (set-box! edit-start #f)
     #f]
    [(and writing? (unbox edit-start))
       (if (string=? (unbox edit-mode) "text")
           (blockview-text-overlay session raw width height got)
           (blockview-edit-overlay session raw width height got))]
    [writing? #f]
    [else (blockview-view-overlay session raw width height got)]))

