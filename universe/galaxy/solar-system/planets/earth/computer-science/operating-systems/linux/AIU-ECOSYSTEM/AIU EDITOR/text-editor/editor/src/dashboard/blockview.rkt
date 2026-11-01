#lang racket/base
;; One job: the block cursor and the block edit of a page in the live session.
;; In the view layer the block under the point is lit. The keys up and down move
;; the point from block to block, the key i edits only its text inside its box, and the key w opens only that block as raw
;; text while every other block stays drawn. Nothing here edits text: the edit
;; is the write layer, kept inside one block.

(require racket/list
         racket/string
         "../commands/commands.rkt"
         "../machine/terminal.rkt"
         "../notation/document.rkt"
         "../notation/host.rkt")

;; edit-start holds the start offset of the block being edited, or nothing.
(define edit-start (box #f))

;; edit-mode holds raw when the whole block is edited and text when only its text is.
(define edit-mode (box "raw"))

;; edit-lo holds the lowest byte the point may reach while a block is edited.
(define edit-lo (box 0))

;; top-line holds the first line of the view while it follows the lit block.
(define top-line (box 1))

;; view-cache holds the last drawing: the text it was drawn from, the width and
;; the drawing itself.
(define view-cache (box #f))

;; drawn-view answers the page as the notation draws it, for the text as it
;; stands. The last drawing is kept, so a key that changes nothing on the page
;; asks for nothing again.
(define (drawn-view session raw width)
  (define hit (unbox view-cache))
  (if (and hit (equal? (car hit) raw) (equal? (cadr hit) width))
      (caddr hit)
      (let ([drawn (view-of (session-file session) (session-journal session) width)])
        (set-box! view-cache (list raw width drawn))
        drawn)))

;; bv-aiu? answers whether the session edits a page of the notation.
(define (bv-aiu? session)
  (string-suffix? (path->string (session-file session)) ".aiu"))

;; bv-width answers the width of the terminal, the width the screen draws at.
(define (bv-width)
  (let-values ([(w h) (terminal-size)])
    w))

;; bv-plain answers a line of the drawing without its colour codes.
(define (bv-plain line)
  (regexp-replace* #px"\u001b\\[[0-9;]*m" line ""))

;; bv-light answers a line in reverse video. The line may carry colours of its
;; own, so reverse video is put back after each reset.
(define (bv-light line)
  (string-append "\u001b[7m"
                 (regexp-replace* #px"\u001b\\[0?m" line "\u001b[0m\u001b[7m")
                 "\u001b[0m"))

;; bv-box is one box of the drawing: its first line, its last line and the
;; boxes drawn inside it. Lines are counted from 0.
(struct bv-box (from to kids))

;; bv-prefix answers the left edge a box of one depth sits behind.
(define (bv-prefix depth)
  (apply string-append (for/list ([i (in-range depth)]) "│ ")))

;; bv-end answers the line where a box that starts at one line ends. A box with
;; a todo has two bottom edges: the first is labelled and the tray follows it.
(define (bv-end lines from limit close-rx label-rx)
  (let loop ([j (add1 from)] [labelled? #f])
    (cond
      [(>= j limit) #f]
      [(regexp-match? close-rx (vector-ref lines j))
       (if (and (not labelled?) (regexp-match? label-rx (vector-ref lines j)))
           (loop (add1 j) #t)
           j)]
      [else (loop (add1 j) labelled?)])))

;; bv-boxes answers the boxes of one depth between two lines of the drawing, each
;; with the boxes inside it.
(define (bv-boxes lines from limit depth)
  (define prefix (regexp-quote (bv-prefix depth)))
  (define top-rx (regexp (string-append "^" prefix "╭─")))
  (define close-rx (regexp (string-append "^" prefix "╰")))
  (define label-rx (regexp (string-append "^" prefix "╰─ ")))
  (let loop ([i from] [out null])
    (cond
      [(>= i limit) (reverse out)]
      [(regexp-match? top-rx (vector-ref lines i))
       (define end (bv-end lines i limit close-rx label-rx))
       (if end
           (loop (add1 end)
                 (cons (bv-box i end (bv-boxes lines (add1 i) end (add1 depth))) out))
           (loop (add1 i) out))]
      [else (loop (add1 i) out)])))

;; bv-kids answers the blocks one level inside a block, in page order.
(define (bv-kids blocks b)
  (filter (lambda (k)
            (and (= (block-depth k) (add1 (block-depth b)))
                 (>= (block-start k) (block-start b))
                 (<= (block-end k) (block-end b))))
          blocks))

;; bv-seen answers the blocks inside a block that the drawing shows as boxes of
;; their own: the answers are not drawn, and the first title of a section is the
;; name on the top edge of the section box.
(define (bv-seen blocks b)
  (define kids
    (filter (lambda (k) (not (string=? (block-name k) "answer")))
            (bv-kids blocks b)))
  (if (and (string=? (block-name b) "section")
           (pair? kids)
           (string=? (block-name (car kids)) "title"))
      (cdr kids)
      kids))

;; bv-assign puts blocks and boxes side by side, in order, and answers the lines
;; each block fills, keyed by the start of the block. A level where the counts
;; differ is left unmatched, so no block is ever given the wrong lines.
(define (bv-assign blocks wanted boxes ranges)
  (if (= (length wanted) (length boxes))
      (for/fold ([found ranges]) ([b (in-list wanted)] [bx (in-list boxes)])
        (define next
          (hash-set found (block-start b) (cons (bv-box-from bx) (bv-box-to bx))))
        (if (member (block-name b) (list "section" "comment"))
            (bv-assign blocks (bv-seen blocks b) (bv-box-kids bx) next)
            next))
      ranges))

;; bv-ranges answers the lines of the drawing each block fills, keyed by the
;; start of the block.
(define (bv-ranges got lines)
  (define plain (list->vector (map bv-plain lines)))
  (define blocks (page-blocks got))
  (define top
    (filter (lambda (b)
              (and (= (block-depth b) 0) (not (string=? (block-name b) "answer"))))
            blocks))
  (bv-assign blocks top (bv-boxes plain 0 (vector-length plain) 0) (hash)))

;; bv-drawn answers the blocks the cursor can stand on: every block the drawing
;; shows as a box.
(define (bv-drawn blocks)
  (define hidden
    (for/list ([b (in-list blocks)] #:when (string=? (block-name b) "section"))
      (define kids (bv-kids blocks b))
      (if (and (pair? kids) (string=? (block-name (car kids)) "title"))
          (block-start (car kids))
          -1)))
  (filter (lambda (b)
            (and (not (string=? (block-name b) "answer"))
                 (not (memv (block-start b) hidden))))
          blocks))

;; bv-inside answers the innermost block that holds a byte offset, or nothing.
(define (bv-inside blocks point)
  (define inside
    (filter (lambda (b) (and (<= (block-start b) point) (< point (block-end b))))
            blocks))
  (if (null? inside) #f (argmax block-depth inside)))

;; bv-target answers the block to light: the innermost block at the point whose
;; lines are known.
(define (bv-target blocks point ranges)
  (bv-inside (filter (lambda (b) (hash-has-key? ranges (block-start b))) blocks)
             point))

;; bv-follow answers the first line to show so that the lines from to to are in
;; the window. A block taller than the window shows from its first line.
(define (bv-follow from to visible)
  (define shown (unbox top-line))
  (define next
    (cond
      [(< from shown) from]
      [(> to (+ shown visible -1))
       (if (>= (- to from) visible) from (max 1 (+ (- to visible) 1)))]
      [else shown]))
  (set-box! top-line next)
  next)

;; lit-range holds the first and last line of the lit block as last placed, or #f.
(define lit-range (box #f))

;; free-block holds #t after a scroll key, then the start line of the block the scroll belongs to, or #f when the view is centred.
(define free-block (box #f))

;; bv-place answers the first line to show: after a scroll key the view stays where it was moved but the lit block stays on screen, otherwise the block is centred.
(define (bv-place from to visible)
  (define fbv (unbox free-block))
  (set-box! lit-range (cons from to))
  (cond
    [(and fbv (or (eq? fbv #t) (eqv? fbv from)))
     (set-box! free-block from)
     (let* ([lo (max 1 (+ (- to visible) 1))]
            [next (max 1 (unbox top-line))])
       (set-box! top-line next)
       next)]
    [else (set-box! free-block #f) (bv-center from to visible)]))

;; bv-command-view-up scrolls the view up by 3 lines.
(define (bv-command-view-up session words)
  (set-box! top-line (max 1 (- (unbox top-line) 3)))
  (set-box! free-block #t)
  (cons #t "view up"))

;; bv-command-view-down scrolls the view down by 3 lines.
(define (bv-command-view-down session words)
  (set-box! top-line (+ (unbox top-line) 3))
  (set-box! free-block #t)
  (cons #t "view down"))

;; bv-center answers the first line to show so that the lines from to to sit in the middle of the window; a block taller than the window shows from its first line.
(define (bv-center from to visible)
  (define next (if (>= (- to from) visible) from (max 1 (- (quotient (+ from to) 2) (quotient visible 2)))))
  (set-box! top-line next)
  next)

;; bv-view-overlay answers the drawing with the block at the point lit, the
;; point and the first line to show, or nothing when no block can be lit.
(define (bv-view-overlay-base session raw width height got)
  (define lines (string-split (drawn-view session raw width) "\n" #:trim? #f))
  (define ranges (bv-ranges got lines))
  (define target (bv-target (page-blocks got) (the-point session) ranges))
  (define range (and target (hash-ref ranges (block-start target))))
  (and range
       (list (string-join
              (for/list ([l (in-list lines)] [i (in-naturals)])
                (let ([lit? (or (<= (car range) i (cdr range)) (ormap (lambda (r) (<= (car r) i (cdr r))) (bv-multi-lit session got ranges)))]) (if (and (getenv "AIU_FOCUS_COLOURS") (not lit?)) "" (string-append (if lit? "\u001b[97m" "\u001b[90m") (bv-plain l) "\u001b[0m"))))
              "\n")
             (the-point session)
             (bv-place (add1 (car range)) (add1 (cdr range)) (max 1 (- height 1))))))

;; pins holds the pinned boxes, each a list of the block start line, the place top or bottom, hidden and keep-in-focus; unset until first used.
(define pins (box (quote unset)))

;; pin-sel holds the index of the pinned box the pin keys act on.
(define pin-sel (box 0))

;; cur-start holds the start line of the block at the point as of the last drawing.
(define cur-start (box #f))

;; first-start holds the start line of the first block of the page.
(define first-start (box #f))

;; pins-now answers the list of pins and makes the first block the default pin on first use.
(define (pins-now)
  (when (eq? (unbox pins) (quote unset))
    (set-box! pins (if (unbox first-start) (list (list (unbox first-start) "top" #f #t)) (list))))
  (unbox pins))

;; pin-update! replaces the pin at the selected index with the result of f.
(define (pin-update! f)
  (set-box! pins (for/list ([p (in-list (pins-now))] [j (in-naturals)]) (if (= j (unbox pin-sel)) (f p) p))))

;; bv-command-pin-mode enters the pin layer.
(define (bv-command-pin-mode session words)
  (pins-now)
  (set-layer! session "pin")
  (cons #t "layer: pin"))

;; bv-command-pin-add pins the block at the point at the top and selects it.
(define (bv-command-pin-add session words)
  (define all (pins-now))
  (cond
    [(not (unbox cur-start)) (cons #t "pin: no block")]
    [(ormap (lambda (p) (equal? (car p) (unbox cur-start))) all) (cons #t "pin: already pinned")]
    [else (set-box! pins (append all (list (list (unbox cur-start) "top" #f #f))))
          (set-box! pin-sel (length all))
          (cons #t "pin: added")]))

;; bv-command-pin-delete deletes the selected pin, the first block too.
(define (bv-command-pin-delete session words)
  (define all (pins-now))
  (cond
    [(null? all) (cons #t "pin: none")]
    [else
     (define i (min (unbox pin-sel) (- (length all) 1)))
     (set-box! pins (for/list ([p (in-list all)] [j (in-naturals)] #:unless (= j i)) p))
     (set-box! pin-sel (max 0 (min i (- (length all) 2))))
     (cons #t "pin: deleted")]))

;; bv-command-pin-next selects the next pin.
(define (bv-command-pin-next session words)
  (define n (length (pins-now)))
  (when (> n 0) (set-box! pin-sel (modulo (add1 (unbox pin-sel)) n)))
  (cons #t "pin: next"))

;; bv-command-pin-prev selects the previous pin.
(define (bv-command-pin-prev session words)
  (define n (length (pins-now)))
  (when (> n 0) (set-box! pin-sel (modulo (+ (unbox pin-sel) n -1) n)))
  (cons #t "pin: previous"))

;; bv-command-pin-top puts the selected pin on the top edge.
(define (bv-command-pin-top session words)
  (pin-update! (lambda (p) (list (car p) "top" (caddr p) (cadddr p))))
  (cons #t "pin: top"))

;; bv-command-pin-bottom puts the selected pin on the bottom edge.
(define (bv-command-pin-bottom session words)
  (pin-update! (lambda (p) (list (car p) "bottom" (caddr p) (cadddr p))))
  (cons #t "pin: bottom"))

;; bv-command-pin-hide hides or shows the selected pin.
(define (bv-command-pin-hide session words)
  (pin-update! (lambda (p) (list (car p) (cadr p) (not (caddr p)) (cadddr p))))
  (cons #t "pin: hide toggled"))

;; bv-command-pin-keep keeps the selected pin visible in focus mode, or hides it there again.
(define (bv-command-pin-keep session words)
  (pin-update! (lambda (p) (list (car p) (cadr p) (caddr p) (not (cadddr p)))))
  (cons #t "pin: keep in focus toggled"))

;; pin-swap! swaps two pins by index and selects the second place.
(define (pin-swap! a b)
  (define v (list->vector (pins-now)))
  (when (and (<= 0 a) (< a (vector-length v)) (<= 0 b) (< b (vector-length v)))
    (let ([t (vector-ref v a)]) (vector-set! v a (vector-ref v b)) (vector-set! v b t))
    (set-box! pins (vector->list v))
    (set-box! pin-sel b)))

;; bv-command-pin-earlier moves the selected pin one step earlier in the stack of its edge.
(define (bv-command-pin-earlier session words)
  (pin-swap! (unbox pin-sel) (- (unbox pin-sel) 1))
  (cons #t "pin: earlier"))

;; bv-command-pin-later moves the selected pin one step later in the stack of its edge.
(define (bv-command-pin-later session words)
  (pin-swap! (unbox pin-sel) (+ (unbox pin-sel) 1))
  (cons #t "pin: later"))

;; bv-view-overlay answers the floating drawing with every shown pin copied onto its screen edge when its block has scrolled out of the window.
(define (bv-view-overlay session raw width height got)
  (define lines (string-split (drawn-view session raw width) "\n" #:trim? #f))
  (define ranges (bv-ranges got lines))
  (define bl (page-blocks got))
  (define target (bv-target bl (the-point session) ranges))
  (set-box! cur-start (and target (block-start target)))
  (when (pair? bl) (set-box! first-start (block-start (car bl))))
  (define r (bv-view-overlay-float session raw width height got))
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
              (vector-set! v (+ start j) (if (< idx (vector-length lv)) (string-append colour (bv-plain (vector-ref lv idx)) "\u001b[0m") "")))
            (loop (cdr all) (add1 i) (if top? (+ to k) to) (if top? bo (+ bo k)))]
           [else (loop (cdr all) (add1 i) to bo)])))
     (list (string-join (vector->list v) "\n") (cadr r) top)]
    [else r]))

;; bv-view-overlay answers the base drawing, and after a scroll key it copies the lit block onto the bottom edge of the window when the block is below it, or the top edge when it is above it.
(define (bv-view-overlay-float session raw width height got)
  (define r (bv-view-overlay-base session raw width height got))
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

;; bv-edit-overlay answers the drawing with the block being edited shown as raw
;; text, with its start and end lines, and every other block drawn. The raw lines
;; sit behind the left edge of the box that holds the block, and a line wider than
;; the screen is cut at a space with the edge drawn on every part, so the boxes
;; around stay in place. It answers the point and the first line to show, or
;; nothing when the block can no longer be found.
(define (bv-edit-overlay session raw width height got)
  (define start (unbox edit-start))
  (define b
    (for/first ([x (in-list (page-blocks got))] #:when (= (block-start x) start))
      x))
  (define lines (string-split (drawn-view session raw width) "\n" #:trim? #f))
  (define range (and b (hash-ref (bv-ranges got lines) start #f)))
  (cond
    [(not range)
     (set-box! edit-start #f)
     #f]
    [else
     (define bs (string->bytes/utf-8 raw))
     (define end (min (block-end b) (bytes-length bs)))
     (define edge (bv-prefix (block-depth b)))
     (define before (take lines (car range)))
     (define after (drop lines (min (length lines) (add1 (cdr range)))))
     (define wb (max 12 (- (string-length (bv-plain (list-ref lines (car range)))) (* 4 (block-depth b)))))
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
     (define parts (for/list ([l (in-list text-lines)]) (bv-chunks l cw)))
     (define shown
       (for*/list ([(l ps) (in-parallel text-lines parts)] [p (in-list ps)])
         (string-append edge (bv-pad (substring l (car p) (cdr p)) cw) tail)))
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
           (bv-follow row row (max 1 (- height 1))))]))

;; block-overlay answers what the live screen draws for a page: the text, the
;; point and the first line, or nothing when the plain screen should be used.
(define (block-overlay session raw width height)
  (define r0 (block-overlay-base session raw width height))
  (define pg (and (not r0) (getenv "AIU_FOCUS_COLOURS") (string=? (the-layer session) "write") (page-of (session-file session) (session-journal session))))
  (define r (or r0 (and pg (page? pg) (bv-view-overlay session raw width height pg))))
  (define got (and r (getenv "AIU_FOCUS_COLOURS") (string=? (the-layer session) "write") (unbox edit-start) (page-of (session-file session) (session-journal session))))
  (cond
    [(and got (page? got))
     (define lines (string-split (drawn-view session raw width) "\n" #:trim? #f))
     (define range (hash-ref (bv-ranges got lines) (unbox edit-start) #f))
     (cond
       [range
        (define out (string-split (car r) "\n" #:trim? #f))
        (define nb (car range))
        (define na (max 0 (- (length lines) (cdr range) 1)))
        (define total (length out))
        (define lost (for/sum ([l (in-list out)] [i (in-range nb)]) (bytes-length (string->bytes/utf-8 l))))
        (list (string-join (for/list ([l (in-list out)] [i (in-naturals)]) (if (or (< i nb) (>= i (- total na))) "" l)) "\n")
              (- (cadr r) lost)
              (caddr r))]
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
           (bv-text-overlay session raw width height got)
           (bv-edit-overlay session raw width height got))]
    [writing? #f]
    [else (bv-view-overlay session raw width height got)]))

;; bv-clamp! puts the point back inside the block being edited.
(define (bv-clamp! session start)
  (define got (page-of (session-file session) (session-journal session)))
  (define b
    (and (page? got)
         (for/first ([x (in-list (page-blocks got))] #:when (= (block-start x) start))
           x)))
  (when b
    (define p (the-point session))
    (cond
      [(< p (unbox edit-lo)) (move-to session (unbox edit-lo))]
      [(> p (bv-hi session b)) (move-to session (bv-hi session b))]
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
     (bv-clamp! session start)
     result]))

;; bv-first-content answers the offset of the second line of a block, where its
;; text begins, or the start of the block when it has one line.
(define (bv-first-content raw b)
  (define bs (string->bytes/utf-8 raw))
  (define end (min (block-end b) (bytes-length bs)))
  (let loop ([i (block-start b)])
    (cond
      [(>= i end) (block-start b)]
      [(= (bytes-ref bs i) 10) (min end (add1 i))]
      [else (loop (add1 i))])))

;; bv-step moves the point to the next block (direction 1) or the previous one
;; (direction -1). A file that is not a page scrolls the view instead.
(define (bv-step session words direction fallback)
  (define got (and (bv-aiu? session)
                   (page-of (session-file session) (session-journal session))))
  (cond
    [(not (page? got)) ((hash-ref commands fallback) session words)]
    [else
     (define blocks (filter bv-kind-match? (bv-drawn (page-blocks got))))
     (define p (the-point session))
     (define current (bv-inside blocks p))
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

;; bv-command-up lights the block before this one.
(define (bv-command-up session words)
  (bv-step session words -1 "view-up"))

;; bv-command-down lights the block after this one.
(define (bv-command-down session words)
  (bv-step session words 1 "view-down"))

;; bv-command-edit opens the lit block as raw text in the write layer. Every
;; other block stays drawn. A block whose lines cannot be told opens the whole
;; page to write, as the write layer always did.
(define (bv-command-edit session words)
  (define got (and (bv-aiu? session)
                   (page-of (session-file session) (session-journal session))))
  (cond
    [(not (page? got)) (cons #t "block edit needs a page of the notation that can be read")]
    [else
     (define raw (session-text session))
     (define lines (string-split (drawn-view session raw (bv-width)) "\n" #:trim? #f))
     (define ranges (bv-ranges got lines))
     (define target (bv-target (page-blocks got) (the-point session) ranges))
     (set-layer! session "write")
     (cond
       [target
        (set-box! edit-start (block-start target))
         (set-box! edit-mode "raw")
         (set-box! edit-lo (block-start target))
        (move-to session (bv-first-content raw target))
        (cons #t (format "editing the ~a block: escape draws the page again"
                         (block-name target)))]
       [else
        (set-box! edit-start #f)
        (cons #t "no block is lit here: the whole page is open to write")])]))

;; bv-content answers the byte range of the text lines of a leaf block: from the
;; second line to the end of the line before the end line. Nothing when the block
;; has no text line.
(define (bv-content raw b)
  (define bs (string->bytes/utf-8 raw))
  (define end (min (block-end b) (bytes-length bs)))
  (define lo (bv-first-content raw b))
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

;; bv-hi answers the highest byte the point may reach while a block is edited.
(define (bv-hi session b)
  (define span
    (and (string=? (unbox edit-mode) "text")
         (bv-content (session-text session) b)))
  (if span (cdr span) (block-end b)))

;; bv-pad answers a string padded with spaces on the right to n characters.
(define (bv-pad s n)
  (if (< (string-length s) n)
      (string-append s (make-string (- n (string-length s)) #\space))
      s))

;; bv-chunks answers how one line of text is cut into parts of at most cw
;; characters, as pairs of the first and the end character of each part. A part
;; ends after a space when there is one, so a word is split only when it is
;; longer than a part.
(define (bv-chunks line cw)
  (define len (string-length line))
  (let loop ([i 0] [out null])
    (cond
      [(<= (- len i) cw) (reverse (cons (cons i len) out))]
      [else
       (define cut
         (or (for/first ([j (in-range (+ i cw -1) (sub1 i) -1)]
                         #:when (char=? (string-ref line j) #\space))
               (add1 j))
             (+ i cw)))
       (loop cut (cons (cons i cut) out))])))

;; bv-text-overlay answers the drawing with the text lines of the block being
;; edited shown raw inside the drawn box of the block: the top edge, the bottom
;; edge and every other block stay drawn, and the start and end lines stay hidden.
;; A text line wider than the box is cut at a space into parts, and the left edge
;; of the box is drawn on every part, so the box stays clean. Nothing when the
;; block can no longer be found.
(define (bv-text-overlay session raw width height got)
  (define start (unbox edit-start))
  (define b
    (for/first ([x (in-list (page-blocks got))] #:when (= (block-start x) start))
      x))
  (define lines (string-split (drawn-view session raw width) "\n" #:trim? #f))
  (define range (and b (hash-ref (bv-ranges got lines) start #f)))
  (define span (and b range (bv-content raw b)))
  (cond
    [(not span)
     (set-box! edit-start #f)
     #f]
    [else
     (define bs (string->bytes/utf-8 raw))
     (define lo (car span))
     (define hi (cdr span))
     (define edge (string-append (bv-prefix (block-depth b)) "│ "))
     (define plain (list->vector (map bv-plain lines)))
     (define bottom-rx
       (regexp (string-append "^" (regexp-quote (bv-prefix (block-depth b))) "╰")))
     (define bottom
       (or (for/first ([i (in-range (add1 (car range)) (add1 (cdr range)))]
                       #:when (regexp-match? bottom-rx (vector-ref plain i)))
             i)
           (cdr range)))
     (define before (take lines (add1 (car range))))
     (define after (drop lines bottom))
     (define wb (max 12 (- (string-length (bv-plain (list-ref lines (car range)))) (* 4 (block-depth b)))))
     (define tail (apply string-append (for/list ([i (in-range (block-depth b))]) " │")))
     (define cw (max 8 (- wb 4)))
     (define rel (max 0 (min (- (the-point session) lo) (- hi lo))))
     (define text-lines
       (string-split (bytes->string/utf-8 (subbytes bs lo hi) #\?) "\n" #:trim? #f))
     (define k
       (min (sub1 (length text-lines))
            (for/sum ([c (in-bytes (subbytes bs lo (+ lo rel)))]) (if (= c 10) 1 0))))
     (define line-start
       (let loop ([i (+ lo rel)])
         (if (or (<= i lo) (= (bytes-ref bs (sub1 i)) 10)) (max i lo) (loop (sub1 i)))))
     (define col
       (string-length (bytes->string/utf-8 (subbytes bs line-start (+ lo rel)) #\?)))
     (define parts (for/list ([l (in-list text-lines)]) (bv-chunks l cw)))
     (define shown
       (for*/list ([(l ps) (in-parallel text-lines parts)] [p (in-list ps)])
         (string-append edge (bv-pad (substring l (car p) (cdr p)) cw) " │" tail)))
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
           (bv-follow row row (max 1 (- height 1))))]))

;; bv-command-text opens only the text of the lit block in the write layer. The
;; block stays drawn in its own box and its start and end lines stay hidden. A
;; block that holds other blocks, or has no text line, opens as raw text like w.
(define (bv-command-text session words)
  (define got (and (bv-aiu? session)
                   (page-of (session-file session) (session-journal session))))
  (define raw (session-text session))
  (define target
    (and (page? got)
         (bv-target (page-blocks got) (the-point session)
                    (bv-ranges got (string-split (drawn-view session raw (bv-width)) "\n" #:trim? #f)))))
  (define span
    (and target
         (null? (bv-kids (page-blocks got) target))
         (bv-content raw target)))
  (cond
    [span
     (set-layer! session "write")
     (set-box! edit-start (block-start target))
     (set-box! edit-mode "text")
     (set-box! edit-lo (car span))
     (move-to session (car span))
     (cons #t (format "editing the text of the ~a block: escape draws the page again"
                      (block-name target)))]
    [else (bv-command-edit session words)]))

;; bv-parent answers the block that holds a block one level up, or nothing.
(define (bv-parent blocks b)
  (define ups
    (filter (lambda (p)
              (and (= (block-depth p) (sub1 (block-depth b)))
                   (<= (block-start p) (block-start b))
                   (>= (block-end p) (block-end b))))
            blocks))
  (if (null? ups) #f (argmax block-start ups)))

;; bv-siblings answers the blocks that sit beside a block under the same parent,
;; in page order. Answers and titles are left out, so they never move.
(define (bv-siblings blocks b)
  (define parent (bv-parent blocks b))
  (sort (filter (lambda (k)
                  (and (= (block-depth k) (block-depth b))
                       (not (member (block-name k) (list "answer" "title")))
                       (equal? (bv-parent blocks k) parent)))
                blocks)
        < #:key block-start))

;; bv-move swaps the lit block with the sibling before (direction -1) or after
;; (direction 1) it, by one delete-at and one insert-at. The point follows the block.
(define (bv-move session direction)
  (define got (and (bv-aiu? session)
                   (page-of (session-file session) (session-journal session))))
  (cond
    [(not (page? got)) (cons #t "block move needs a page of the notation")]
    [else
     (define bs (string->bytes/utf-8 (session-text session)))
     (define cur (bv-inside (bv-drawn (page-blocks got)) (the-point session)))
     (define sibs (if cur (bv-siblings (page-blocks got) cur) null))
     (define idx
       (for/first ([k (in-list sibs)] [n (in-naturals)]
                   #:when (= (block-start k) (block-start cur)))
         n))
     (define other-idx (and idx (+ idx direction)))
     (cond
       [(not idx) (cons #t "no block can move here")]
       [(or (< other-idx 0) (>= other-idx (length sibs)))
        (cons #t "no block there to swap with")]
       [else
        (define other (list-ref sibs other-idx))
        (define a (if (< direction 0) other cur))
        (define b (if (< direction 0) cur other))
        (define a0 (block-start a))
        (define a1 (min (block-end a) (bytes-length bs)))
        (define b0 (block-start b))
        (define b1 (min (block-end b) (bytes-length bs)))
        (define (piece lo hi) (bytes->string/utf-8 (subbytes bs lo hi) #\?))
        (ask session "delete-at"
             (hasheq (quote at) (number->string a0) (quote count) (number->string (- b1 a0))))
        (ask session "insert-at"
             (hasheq (quote at) (number->string a0)
                     (quote text) (string-append (piece b0 b1) (piece a1 b0) (piece a0 a1))))
        (move-to session (if (< direction 0) a0 (+ a0 (- b1 a1))))
        (cons #t (format "moved the ~a block ~a" (block-name cur) (if (< direction 0) "up" "down")))])]))

;; bv-command-move-up swaps the lit block with the one before it.
(define (bv-command-move-up session words)
  (bv-move session -1))

;; bv-command-move-down swaps the lit block with the one after it.
(define (bv-command-move-down session words)
  (bv-move session 1))

;; bv-command-move-mode puts the editor in the move layer.
(define (bv-command-move-mode session words)
  (set-layer! session "move")
  (cons #t "layer: move"))

;; bv-command-leave-write saves, then goes back to the visual layer.
(define (bv-command-leave-write session words)
  ((hash-ref commands "save") session words)
  (set-layer! session "visual")
  (cons #t "saved"))

;; bv-near answers the path of a module found from the folder of this one, or false.
(define (bv-near . parts)
  (let ([src (variable-reference->module-source (#%variable-reference))])
    (and (path? src)
         (let-values ([(base file dir?) (split-path src)])
           (and (path? base) (simplify-path (apply build-path base parts)))))))

;; bv-after-write runs once when the write layer is left: the git row and strip are marked old
;; through edit-hook, and one undo commit is noted in a thread. Nothing runs while typing.
(define (bv-after-write file)
  (with-handlers ([void void])
    (let ([hp (bv-near (quote up) "join" "hot-path.rkt")])
      (when hp ((unbox (dynamic-require hp (quote edit-hook))))))
    (let ([sh (bv-near "shadow.rkt")])
      (when (and sh file)
        (thread (lambda ()
                  (with-handlers ([void void])
                    ((dynamic-require sh (quote shadow-note!)) file))))))))

;; The four keys are added to the command table when this module is loaded, so
;; the keys find them and the gate sees the same table the editor does.
(hash-set! commands "block-up" bv-command-up)
(hash-set! commands "view-up" bv-command-view-up)
(hash-set! commands "view-down" bv-command-view-down)
(hash-set! commands "pin-mode" bv-command-pin-mode)
(hash-set! commands "pin-add" bv-command-pin-add)
(hash-set! commands "pin-delete" bv-command-pin-delete)
(hash-set! commands "pin-next" bv-command-pin-next)
(hash-set! commands "pin-prev" bv-command-pin-prev)
(hash-set! commands "pin-top" bv-command-pin-top)
(hash-set! commands "pin-bottom" bv-command-pin-bottom)
(hash-set! commands "pin-hide" bv-command-pin-hide)
(hash-set! commands "pin-keep" bv-command-pin-keep)
(hash-set! commands "pin-earlier" bv-command-pin-earlier)
(hash-set! commands "pin-later" bv-command-pin-later)
(hash-set! commands "block-down" bv-command-down)
(hash-set! commands "block-edit" bv-command-edit)
(hash-set! commands "block-text" bv-command-text)
(hash-set! commands "block-move-up" bv-command-move-up)
(hash-set! commands "block-move-down" bv-command-move-down)
(hash-set! commands "block-move-mode" bv-command-move-mode)
(hash-set! commands "leave-write" (lambda (session words) (let ([r (bv-command-leave-write session words)]) (set-box! unsaved #f) (bv-after-write (session-file session)) r)))

;; The block view, for the live screen above it.
(provide block-overlay
         block-guard
         drawn-view)

;; bv-todo-state answers done or open for the todo on a block, or false when the block holds no todo. The state is the first word after todo: and no word means open.
(define (bv-todo-state b)
  (define found
    (filter (lambda (d) (member (decl-keyword d) (list "todo" "todo:")))
            (block-decls b)))
  (cond
    [(null? found) #f]
    [else
     (define words (string-split (format "~a" (decl-value (car found)))))
     (if (and (pair? words) (string=? (car words) "done")) "done" "open")]))

;; bv-kind-match? asks whether a block is of the kind the kind layer picked.
(define (bv-kind-match? b)
  (define want (unbox kind-filter))
  (cond
    [(string=? want "any") #t]
    [(string=? want "todo") (and (bv-todo-state b) #t)]
    [(string=? want "todo open") (equal? (bv-todo-state b) "open")]
    [(string=? want "todo done") (equal? (bv-todo-state b) "done")]
    [else (string=? (block-name b) want)]))

;; bv-kind-setter answers a command that picks one kind and says which.
(define (bv-kind-setter want)
  (lambda (session words)
    (set-box! kind-filter want)
    (cons #t (format "kind: ~a" want))))

(for-each
 (lambda (pair) (hash-set! commands (car pair) (bv-kind-setter (cdr pair))))
 (list (cons "kind-any" "any")
       (cons "kind-paragraph" "paragraph")
       (cons "kind-section" "section")
       (cons "kind-code" "code")
       (cons "kind-comment" "comment")
       (cons "kind-title" "title")
       (cons "kind-todo" "todo")
       (cons "kind-todo-open" "todo open")
       (cons "kind-todo-done" "todo done")))
(provide bv-ranges)

;; The save command is wrapped: it saves, clears unsaved, then runs the git refresh and one undo commit.
;; Nothing else saves or commits; typing only marks the file unsaved.
(hash-set! commands "save"
           (let ([orig (hash-ref commands "save")])
             (lambda (session words)
               (let ([r (orig session words)])
                 (set-box! unsaved #f)
                 (bv-after-write (session-file session))
                 r))))

;; bv-multi-cache keeps the lit ranges of the last drawing, keyed by its ranges table.
(define bv-multi-cache (box #f))

;; bv-multi-lit answers the line ranges the extra cursors and the selections light, besides the block at the point.
(define (bv-multi-lit session got ranges)
  (cond
    [(not (multi-live? session)) (list)]
    [else
     (let ([c (unbox bv-multi-cache)])
       (if (and c (eq? (car c) ranges))
           (cdr c)
           (let ([r ((unbox multi-lit-hook) got ranges (the-point session))])
             (set-box! bv-multi-cache (cons ranges r))
             r)))]))

;; The commands that edit or move the point run for every cursor while there are extra cursors: multi.rkt
;; does the work through multi-edit-hook. With no extra cursor the command is the old one.
(for-each
 (lambda (name)
   (hash-set! commands name
              (let ([orig (hash-ref commands name)])
                (lambda (session words)
                  (if (and (or (pair? (unbox extra-cursors)) (unbox main-anchor))
                           (equal? (unbox multi-file) (session-file session))
                           (unbox multi-edit-hook))
                      ((unbox multi-edit-hook) name orig session words)
                      (orig session words))))))
 (list "type" "delete" "move-left" "move-right" "move-up" "move-down"))

;; Opening the block edit drops the extra cursors: the block edit is one place.
(for-each
 (lambda (name)
   (hash-set! commands name
              (let ([orig (hash-ref commands name)])
                (lambda (session words) (multi-clear!) (orig session words)))))
 (list "block-edit" "block-text"))

;; Escape in the visual layer drops the extra cursors and the selections first; escape elsewhere is the old command.
(hash-set! commands "visual-mode"
           (let ([orig (hash-ref commands "visual-mode")])
             (lambda (session words)
               (if (and (string=? (the-layer session) "visual") (multi-live? session))
                   (begin (multi-clear!) (cons #t "cursors cleared"))
                   (orig session words)))))

;; The pieces multi.rkt needs from this module.
(provide bv-kind-match? bv-inside bv-drawn)

;; Leaving the write layer drops the selections: the extra cursors stay, so a second round of writing can follow.
(hash-set! commands "leave-write"
           (let ([orig (hash-ref commands "leave-write")])
             (lambda (session words)
               (let ([r (orig session words)])
                 (multi-drop-selections!)
                 r))))
