#lang racket/base
;; One job: draw the text of a block inside its box and open that text for editing (the block-text key).

(require racket/list racket/string "../../commands/commands.rkt" "../../machine/terminal.rkt" "../../notation/document.rkt" "../../notation/host.rkt" "../float/pins.rkt" "blocks-kind.rkt" "blockview.rkt" "blocks-edit.rkt")

(provide blockview-pad blockview-chunks blockview-text-overlay)

;; blockview-pad answers a string padded with spaces on the right to n characters.
(define (blockview-pad s n)
  (if (< (string-length s) n)
      (string-append s (make-string (- n (string-length s)) #\space))
      s))

;; blockview-chunks answers how one line of text is cut into parts of at most cw
;; characters, as pairs of the first and the end character of each part. A part
;; ends after a space when there is one, so a word is split only when it is
;; longer than a part.
(define (blockview-chunks line cw)
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

;; blockview-text-overlay answers the drawing with the text lines of the block being
;; edited shown raw inside the drawn box of the block: the top edge, the bottom
;; edge and every other block stay drawn, and the start and end lines stay hidden.
;; A text line wider than the box is cut at a space into parts, and the left edge
;; of the box is drawn on every part, so the box stays clean. Nothing when the
;; block can no longer be found.
(define (blockview-text-overlay session raw width height got)
  (define start (unbox edit-start))
  (define b
    (for/first ([x (in-list (page-blocks got))] #:when (= (block-start x) start))
      x))
  (define lines (string-split (drawn-view session raw width) "\n" #:trim? #f))
  (define range (and b (hash-ref (blockview-ranges got lines) start #f)))
  (define span (and b range (blockview-content raw b)))
  (cond
    [(not span)
     (set-box! edit-start #f)
     #f]
    [else
     (define bs (string->bytes/utf-8 raw))
     (define lo (car span))
     (define hi (cdr span))
     (define edge (string-append (blockview-prefix (block-depth b)) "│ "))
     (define plain (list->vector (map blockview-plain lines)))
     (define bottom-rx
       (regexp (string-append "^" (regexp-quote (blockview-prefix (block-depth b))) "╰")))
     (define bottom
       (or (for/first ([i (in-range (add1 (car range)) (add1 (cdr range)))]
                       #:when (regexp-match? bottom-rx (vector-ref plain i)))
             i)
           (cdr range)))
     (define before (take lines (add1 (car range))))
     (define after (drop lines bottom))
     (define wb (max 12 (- (string-length (blockview-plain (list-ref lines (car range)))) (* 4 (block-depth b)))))
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
     (define parts (for/list ([l (in-list text-lines)]) (blockview-chunks l cw)))
     (define shown
       (for*/list ([(l ps) (in-parallel text-lines parts)] [p (in-list ps)])
         (string-append edge (blockview-pad (substring l (car p) (cdr p)) cw) " │" tail)))
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

;; blockview-command-text opens only the text of the lit block in the write layer. The
;; block stays drawn in its own box and its start and end lines stay hidden. A
;; block that holds other blocks, or has no text line, opens as raw text like w.
(define (blockview-command-text session words)
  (define got (and (blockview-aiu? session)
                   (page-of (session-file session) (session-journal session))))
  (define raw (session-text session))
  (define target
    (and (page? got)
         (blockview-target (page-blocks got) (the-point session)
                    (blockview-ranges got (string-split (drawn-view session raw (blockview-width)) "\n" #:trim? #f)))))
  (define span
    (and target
         (null? (blockview-kids (page-blocks got) target))
         (blockview-content raw target)))
  (cond
    [span
     (set-layer! session "write")
     (set-box! edit-start (block-start target))
     (set-box! edit-mode "text")
     (set-box! edit-lo (car span))
     (move-to session (car span))
     (cons #t (format "editing the text of the ~a block: escape draws the page again"
                      (block-name target)))]
    [else (blockview-command-edit session words)]))

;; Opening the text edit drops the extra cursors: the block edit is one place.
(hash-set! commands "block-text" (lambda (session words) (multi-clear!) (blockview-command-text session words)))
