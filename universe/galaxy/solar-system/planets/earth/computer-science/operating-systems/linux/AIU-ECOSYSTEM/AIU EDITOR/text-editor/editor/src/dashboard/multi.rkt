#lang racket/base
;; multi.rkt: multiple cursors and the selection mode. Every cursor can carry a region (an anchor and a head), so
;; several things can be selected at once, as text (characters, lines, words) or as blocks of the picked kind.
;; The state lives in boxes of commands.rkt (extra-cursors, main-anchor, multi-raw-view, multi-file); this module
;; holds the commands and the drawing hooks. There is no limit on the number of cursors. Loaded on first use through
;; the stubs at the end of bar.rkt. Nothing here runs while typing unless extra cursors exist.

(require "../commands/commands.rkt"
         "../notation/document.rkt"
         "../notation/host.rkt"
         (only-in "blockview.rkt" bv-kind-match? bv-inside bv-drawn)
         (only-in "bar.rkt" multi-table)
         (only-in "notify.rkt" notify!))

;; mu-say shows a short message in a notification box.
(define (mu-say text) (notify! "info" text))

;; mu-bytes answers the text of the session as bytes; every offset is a byte offset.
(define (mu-bytes session) (string->bytes/utf-8 (session-text session)))

;; mu-cont? asks whether a byte is the inside of a multi byte character.
(define (mu-cont? b) (= (bitwise-and b 192) 128))

;; mu-left answers the start of the character before an offset.
(define (mu-left bs i)
  (let loop ([j (max 0 (sub1 (min i (bytes-length bs))))])
    (if (and (> j 0) (mu-cont? (bytes-ref bs j))) (loop (sub1 j)) j)))

;; mu-right answers the start of the character after an offset.
(define (mu-right bs i)
  (let ([n (bytes-length bs)])
    (let loop ([j (min n (add1 i))])
      (if (and (< j n) (mu-cont? (bytes-ref bs j))) (loop (add1 j)) j))))

;; mu-line-start answers the start of the line an offset is on.
(define (mu-line-start bs i)
  (let loop ([j (min i (bytes-length bs))])
    (if (or (<= j 0) (= (bytes-ref bs (sub1 j)) 10)) (max j 0) (loop (sub1 j)))))

;; mu-line-end answers the end of the line an offset is on.
(define (mu-line-end bs i)
  (let ([n (bytes-length bs)])
    (let loop ([j (min i n)])
      (if (or (>= j n) (= (bytes-ref bs j) 10)) j (loop (add1 j))))))

;; mu-col answers the column of an offset in characters.
(define (mu-col bs i)
  (for/sum ([k (in-range (mu-line-start bs i) (min i (bytes-length bs)))])
    (if (mu-cont? (bytes-ref bs k)) 0 1)))

;; mu-at-col answers the offset of a column in the line that runs from ls to le, kept inside the line.
(define (mu-at-col bs ls le c)
  (let loop ([j ls] [k 0])
    (if (or (>= j le) (>= k c)) j (loop (mu-right bs j) (add1 k)))))

;; mu-up answers the offset one line up in the same column, or the same offset on the first line.
(define (mu-up bs i)
  (let ([ls (mu-line-start bs i)])
    (if (= ls 0)
        i
        (let* ([pe (sub1 ls)] [ps (mu-line-start bs pe)])
          (mu-at-col bs ps pe (mu-col bs i))))))

;; mu-down answers the offset one line down in the same column, or the same offset on the last line.
(define (mu-down bs i)
  (let ([le (mu-line-end bs i)] [n (bytes-length bs)])
    (if (>= le n)
        i
        (let* ([ns (add1 le)] [ne (mu-line-end bs ns)])
          (mu-at-col bs ns ne (mu-col bs i))))))

;; mu-word? asks whether a byte belongs to a word.
(define (mu-word? b)
  (or (and (>= b 48) (<= b 57)) (and (>= b 65) (<= b 90)) (and (>= b 97) (<= b 122)) (= b 95) (>= b 128)))

;; mu-word-fwd answers the end of the next word.
(define (mu-word-fwd bs i)
  (let ([n (bytes-length bs)])
    (let skip ([j (min i n)])
      (cond [(>= j n) n]
            [(mu-word? (bytes-ref bs j))
             (let eat ([k j]) (if (and (< k n) (mu-word? (bytes-ref bs k))) (eat (add1 k)) k))]
            [else (skip (add1 j))]))))

;; mu-word-back answers the start of the word before an offset.
(define (mu-word-back bs i)
  (let skip ([j (min i (bytes-length bs))])
    (cond [(<= j 0) 0]
          [(mu-word? (bytes-ref bs (sub1 j)))
           (let eat ([k j]) (if (and (> k 0) (mu-word? (bytes-ref bs (sub1 k)))) (eat (sub1 k)) k))]
          [else (skip (sub1 j))])))

;; mu-word-at answers the word under an offset as (start . end); the two are equal when there is none.
(define (mu-word-at bs i)
  (let* ([n (bytes-length bs)]
         [p (min i n)]
         [a (let loop ([k p]) (if (and (> k 0) (mu-word? (bytes-ref bs (sub1 k)))) (loop (sub1 k)) k))]
         [b (let loop ([k p]) (if (and (< k n) (mu-word? (bytes-ref bs k))) (loop (add1 k)) k))])
    (cons a b)))

;; mu-begin! forgets cursors that belong to another file and marks the file of the cursors.
(define (mu-begin! session)
  (unless (equal? (unbox multi-file) (session-file session))
    (multi-clear!))
  (set-box! multi-file (session-file session)))

;; mu-cursors answers every cursor as a vector of its head, its anchor (or false) and whether it is the main one.
(define (mu-cursors session)
  (cons (vector (the-point session) (unbox main-anchor) #t)
        (map (lambda (c) (vector (car c) (cdr c) #f)) (unbox extra-cursors))))

;; mu-total answers how many cursors there are, the main one included.
(define (mu-total) (add1 (length (unbox extra-cursors))))

;; mu-store! keeps a list of cursors: sorted by head, two at one place made one, the main one back in the point.
(define (mu-store! session cs)
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

;; mu-blocks answers the blocks of the picked kind, oldest first, or false when the file is not a page.
(define (mu-blocks session)
  (let ([got (page-of (session-file session) (session-journal session))])
    (and (page? got)
         (sort (filter bv-kind-match? (bv-drawn (page-blocks got))) < #:key block-start))))

;; mu-add-line adds a cursor one line below the lowest cursor (step 1) or above the highest one (step -1).
(define (mu-add-line session step)
  (mu-begin! session)
  (let* ([bs (mu-bytes session)]
         [cs (mu-cursors session)]
         [heads (map (lambda (c) (vector-ref c 0)) cs)]
         [edge (if (> step 0) (apply max heads) (apply min heads))]
         [new (if (> step 0) (mu-down bs edge) (mu-up bs edge))])
    (cond [(= new edge) (mu-say "no line there") (cons #t "none")]
          [else (mu-store! session (cons (vector new #f #f) cs))
                (mu-say (format "cursors: ~a" (mu-total)))
                (cons #t "added")])))

;; mu-add-block adds a cursor at the start of the next block (or the one before) of the picked kind.
(define (mu-add-block session forward?)
  (mu-begin! session)
  (let ([blocks (mu-blocks session)])
    (cond
      [(not blocks) (mu-add-line session (if forward? 1 -1))]
      [else
       (let* ([cs (mu-cursors session)]
              [heads (map (lambda (c) (vector-ref c 0)) cs)]
              [b (if forward?
                     (let ([m (apply max heads)])
                       (for/first ([x (in-list blocks)] #:when (> (block-start x) m)) x))
                     (let ([m (apply min heads)])
                       (for/first ([x (in-list (reverse blocks))] #:when (< (block-start x) m)) x)))])
         (cond [b (mu-store! session (cons (vector (block-start b) #f #f) cs))
                  (mu-say (format "cursors: ~a" (mu-total)))
                  (cons #t "added")]
               [else (mu-say "no block there") (cons #t "none")]))])))

;; mu-needle answers the text to look for: the selected text of the main cursor, or the word under it,
;; which then becomes selected. False when there is neither.
(define (mu-needle session bs)
  (let* ([n (bytes-length bs)]
         [h (min (the-point session) n)]
         [a (and (unbox main-anchor) (min (unbox main-anchor) n))])
    (cond
      [(and a (not (= a h))) (subbytes bs (min a h) (max a h))]
      [else
       (let ([w (mu-word-at bs h)])
         (and (< (car w) (cdr w))
              (begin (set-box! main-anchor (car w))
                     (move-to session (cdr w))
                     (subbytes bs (car w) (cdr w)))))])))

;; mu-add-match adds a cursor with a selection on the next place that holds the needle.
(define (mu-add-match session)
  (mu-begin! session)
  (let* ([bs (mu-bytes session)] [needle (mu-needle session bs)])
    (cond
      [(not needle) (mu-say "no word here") (cons #t "none")]
      [else
       (let* ([cs (mu-cursors session)]
              [from (apply max (map (lambda (c) (max (vector-ref c 0) (or (vector-ref c 1) 0))) cs))]
              [m (regexp-match-positions (byte-regexp (regexp-quote needle)) bs (min from (bytes-length bs)))])
         (cond [m (mu-store! session (cons (vector (cdar m) (caar m) #f) cs))
                  (mu-say (format "cursors: ~a" (mu-total)))
                  (cons #t "added")]
               [else (mu-say "no more matches") (cons #t "none")]))])))

;; mu-add-all adds a cursor with a selection on every place that holds the needle.
(define (mu-add-all session)
  (mu-begin! session)
  (let* ([bs (mu-bytes session)] [needle (mu-needle session bs)])
    (cond
      [(not needle) (mu-say "no word here") (cons #t "none")]
      [else
       (let* ([ms (regexp-match-positions* (byte-regexp (regexp-quote needle)) bs)]
              [cs (mu-cursors session)]
              [have (map (lambda (c) (vector-ref c 0)) cs)]
              [added (for/list ([m (in-list ms)] #:unless (member (cdr m) have))
                       (vector (cdr m) (car m) #f))])
         (mu-store! session (append cs added))
         (mu-say (format "cursors: ~a" (mu-total)))
         (cons #t "added"))])))

;; mu-drop takes the last extra cursor away.
(define (mu-drop session)
  (let ([ex (unbox extra-cursors)])
    (cond [(null? ex) (mu-say "only the main cursor is left") (cons #t "none")]
          [else (set-box! extra-cursors (reverse (cdr (reverse ex))))
                (mu-say (format "cursors: ~a" (mu-total)))
                (cons #t "dropped")])))

;; mu-clear drops every extra cursor and every selection.
(define (mu-clear session)
  (multi-clear!)
  (mu-say "cursors cleared")
  (cons #t "cleared"))

;; mu-cursor-mode opens the cursor layer.
(define (mu-cursor-mode session)
  (mu-begin! session)
  (set-layer! session "cursor")
  (mu-say "cursor: t h blocks, arrows lines, j match, v all, r drop, z clear, f write, s select")
  (cons #t "layer: cursor"))

;; mu-cursor-leave goes back to the visual layer and keeps the cursors.
(define (mu-cursor-leave session)
  (set-layer! session "visual")
  (cons #t "layer: visual"))

;; mu-select-mode opens the select layer: every cursor starts a selection where it stands.
(define (mu-select-mode session)
  (mu-begin! session)
  (mu-store! session
             (for/list ([c (in-list (mu-cursors session))])
               (vector (vector-ref c 0) (or (vector-ref c 1) (vector-ref c 0)) (vector-ref c 2))))
  (set-box! multi-raw-view #f)
  (set-layer! session "select")
  (mu-say "select: n s w b arrows text, h t blocks, a p e c k l x o d pick, j v matches, r drop")
  (cons #t "layer: select"))

;; mu-extend moves the head of every cursor with a function of the text and the head; the anchor stays,
;; or starts where the head was. The raw text is shown, so the selection can be seen.
(define (mu-extend session f)
  (mu-begin! session)
  (let ([bs (mu-bytes session)])
    (mu-store! session
               (for/list ([c (in-list (mu-cursors session))])
                 (let ([h (vector-ref c 0)] [a (vector-ref c 1)])
                   (vector (f bs h) (or a h) (vector-ref c 2)))))
    (set-box! multi-raw-view #t)
    (cons #t "selected")))

;; mu-block-cursor grows the selection of one cursor by one block of the picked kind. A cursor without a
;; selection first selects the block it is in.
(define (mu-block-cursor blocks n c forward?)
  (let* ([h (vector-ref c 0)] [a (vector-ref c 1)] [main? (vector-ref c 2)]
         [lo (if a (min a h) h)] [hi (if a (max a h) h)]
         [sel? (and a (not (= a h)))])
    (cond
      [(not sel?)
       (let ([b (or (bv-inside blocks h)
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

;; mu-block-step grows every selection by a block; a file that is not a page grows by a line.
(define (mu-block-step session forward?)
  (mu-begin! session)
  (let ([blocks (mu-blocks session)])
    (cond
      [(not blocks) (mu-extend session (if forward? mu-down mu-up))]
      [else
       (let ([n (bytes-length (mu-bytes session))])
         (mu-store! session
                    (for/list ([c (in-list (mu-cursors session))])
                      (mu-block-cursor blocks n c forward?)))
         (set-box! multi-raw-view #f)
         (cons #t "selected"))])))

;; mu-cancel drops the selections, keeps the extra cursors and goes back to the visual layer.
(define (mu-cancel session)
  (set-box! main-anchor #f)
  (set-box! extra-cursors (map (lambda (c) (cons (car c) #f)) (unbox extra-cursors)))
  (set-box! multi-raw-view #f)
  (set-layer! session "visual")
  (cons #t "selection dropped"))

;; mu-edit-text runs a typing or deleting command at every cursor, from the last one to the first, so no
;; offset moves under a cursor that is still to be done; then every cursor is put where it belongs.
(define (mu-edit-text orig session words)
  (let* ([cs (sort (mu-cursors session) > #:key (lambda (c) (vector-ref c 0)))]
         [res (for/list ([c (in-list cs)])
                (let ([h (vector-ref c 0)])
                  (move-to session h)
                  (orig session words)
                  (let ([p (the-point session)])
                    (vector p (- p h) (vector-ref c 2)))))])
    (let loop ([asc (reverse res)] [shift 0] [out (list)])
      (if (null? asc)
          (mu-store! session out)
          (let* ([r (car asc)] [p (+ (vector-ref r 0) shift)])
            (loop (cdr asc) (+ shift (vector-ref r 1)) (cons (vector p #f (vector-ref r 2)) out)))))
    (cons #t "edited")))

;; mu-move-all moves every cursor one step the way a move command says.
(define (mu-move-all name session)
  (let* ([bs (mu-bytes session)]
         [f (cond [(string=? name "move-left") mu-left]
                  [(string=? name "move-right") mu-right]
                  [(string=? name "move-up") mu-up]
                  [else mu-down])])
    (mu-store! session
               (for/list ([c (in-list (mu-cursors session))])
                 (vector (f bs (vector-ref c 0)) (vector-ref c 1) (vector-ref c 2))))
    (cons #t "moved")))

;; mu-edit is the hook the wrapped type, delete and move commands call while extra cursors exist.
(define (mu-edit name orig session words)
  (if (member name (list "type" "delete"))
      (mu-edit-text orig session words)
      (mu-move-all name session)))

;; mu-lit answers the line ranges to light in the drawn page for the cursors and the selections: the block
;; under a cursor, and every block that lies inside a selection.
(define (mu-lit got ranges point)
  (let* ([blocks (filter (lambda (b) (hash-has-key? ranges (block-start b))) (page-blocks got))]
         [cs (cons (cons point (unbox main-anchor)) (unbox extra-cursors))])
    (apply append
           (for/list ([c (in-list cs)])
             (let ([h (car c)] [a (cdr c)])
               (cond
                 [(and a (not (= a h)))
                  (let ([lo (min a h)] [hi (max a h)])
                    (for/list ([b (in-list blocks)]
                               #:when (and (>= (block-start b) lo) (<= (block-end b) hi)))
                      (hash-ref ranges (block-start b))))]
                 [else
                  (let ([b (bv-inside blocks h)])
                    (if b (list (hash-ref ranges (block-start b))) (list)))]))))))

;; mu-visible-lines answers the (start . end) of each visible line of the raw text.
(define (mu-visible-lines bs top-line visible)
  (let loop ([pos 0] [ln 1])
    (cond
      [(= ln top-line)
       (let take ([ls pos] [k 0] [out (list)])
         (if (or (>= k visible) (> ls (bytes-length bs)))
             (reverse out)
             (let ([le (mu-line-end bs ls)])
               (take (add1 le) (add1 k) (cons (cons ls le) out)))))]
      [else (loop (add1 (mu-line-end bs pos)) (add1 ln))])))

;; mu-seg answers the escape text that draws one piece of a line in reverse video; eol? adds a blank cell
;; for the end of the line.
(define (mu-seg bs ls a b eol? row left width)
  (let* ([col (for/sum ([k (in-range ls a)]) (if (mu-cont? (bytes-ref bs k)) 0 1))]
         [txt (string-append (bytes->string/utf-8 (subbytes bs a b) #\?) (if eol? " " ""))]
         [room (- width col)])
    (if (or (<= room 0) (string=? txt ""))
        ""
        (string-append "\u001b[" (number->string row) ";" (number->string (+ left col 1)) "H\u001b[7m"
                       (if (> (string-length txt) room) (substring txt 0 room) txt)
                       "\u001b[0m"))))

;; mu-text-overlay answers the escape text that draws the selections and the cursors over the raw text:
;; the main cursor is drawn too, except in the write layer where the terminal cursor is it.
(define (mu-text-overlay raw top visible offset left width layer point)
  (let* ([bs (string->bytes/utf-8 raw)]
         [n (bytes-length bs)]
         [nlines (add1 (for/sum ([b (in-bytes bs)]) (if (= b 10) 1 0)))]
         [top-line (max 1 (min top nlines))]
         [lines (mu-visible-lines bs top-line visible)]
         [cs (append (if (string=? layer "write") (list) (list (cons point (unbox main-anchor))))
                     (unbox extra-cursors))]
         [ivs (for/list ([c (in-list cs)] #:when (and (cdr c) (not (= (cdr c) (car c))))) 
                (cons (min (car c) (cdr c)) (max (car c) (cdr c))))]
         [marks (map car cs)])
    (apply string-append
           (for/list ([ln (in-list lines)] [i (in-naturals)])
             (let ([ls (car ln)] [le (cdr ln)] [row (+ offset i 1)])
               (apply string-append
                      (append
                       (for/list ([iv (in-list ivs)])
                         (let* ([lo (car iv)] [hi (cdr iv)]
                                [a (max lo ls)] [b (min hi le)]
                                [eol? (and (<= lo le) (> hi le) (< le n))])
                           (if (or (< a b) eol?)
                               (mu-seg bs ls a (max a b) eol? row left width)
                               "")))
                       (for/list ([p (in-list marks)])
                         (cond [(and (>= p ls) (< p le)) (mu-seg bs ls p (mu-right bs p) #f row left width)]
                               [(= p le) (mu-seg bs ls le le #t row left width)]
                               [else ""])))))))))

;; mu-reg! adds one command to the table of this module.
(define (mu-reg! name f)
  (hash-set! multi-table name (lambda (session words) (f session))))

;; The commands, added when this module is loaded.
(mu-reg! "cursor-mode" mu-cursor-mode)
(mu-reg! "cur-leave" mu-cursor-leave)
(mu-reg! "cur-below" (lambda (s) (mu-add-line s 1)))
(mu-reg! "cur-above" (lambda (s) (mu-add-line s -1)))
(mu-reg! "cur-next-block" (lambda (s) (mu-add-block s #t)))
(mu-reg! "cur-prev-block" (lambda (s) (mu-add-block s #f)))
(mu-reg! "cur-next-match" mu-add-match)
(mu-reg! "cur-all-matches" mu-add-all)
(mu-reg! "cur-drop" mu-drop)
(mu-reg! "cur-clear" mu-clear)
(mu-reg! "select-mode" mu-select-mode)
(mu-reg! "sel-left" (lambda (s) (mu-extend s mu-left)))
(mu-reg! "sel-right" (lambda (s) (mu-extend s mu-right)))
(mu-reg! "sel-up" (lambda (s) (mu-extend s mu-up)))
(mu-reg! "sel-down" (lambda (s) (mu-extend s mu-down)))
(mu-reg! "sel-word" (lambda (s) (mu-extend s mu-word-fwd)))
(mu-reg! "sel-word-back" (lambda (s) (mu-extend s mu-word-back)))
(mu-reg! "sel-block-forward" (lambda (s) (mu-block-step s #t)))
(mu-reg! "sel-block-back" (lambda (s) (mu-block-step s #f)))
(mu-reg! "sel-next-match" mu-add-match)
(mu-reg! "sel-all-matches" mu-add-all)
(mu-reg! "sel-drop" mu-drop)
(mu-reg! "sel-cancel" mu-cancel)
(set-box! multi-edit-hook mu-edit)
(set-box! multi-lit-hook mu-lit)
(set-box! multi-text-hook mu-text-overlay)
