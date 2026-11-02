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
         "../notation/host.rkt"
         "pins.rkt" "blocks-kind.rkt")

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

;; bv-kind-line answers the line shown in focus mode: the box types from the page top down to the lit box in grey on the line above it, and an empty line elsewhere.
(define (bv-kind-line got target range i)
  (if (and (> (car range) 0) (= i (- (car range) 1)))
      (let ([chain (let loop ([b target] [acc (list)])
                     (if b (loop (bv-parent (page-blocks got) b) (cons (block-name b) acc)) acc))])
        (string-append "\u001b[90m" (string-join chain " > ") "\u001b[0m"))
      ""))
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

;; bv-parent answers the block that holds a block one level up, or nothing.
(define (bv-parent blocks b)
  (define ups
    (filter (lambda (p)
              (and (= (block-depth p) (sub1 (block-depth b)))
                   (<= (block-start p) (block-start b))
                   (>= (block-end p) (block-end b))))
            blocks))
  (if (null? ups) #f (argmax block-start ups)))

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
(hash-set! commands "leave-write" (lambda (session words) (let ([r (bv-command-leave-write session words)]) (set-box! unsaved #f) (bv-after-write (session-file session)) r)))

;; The block view, for the live screen above it.
(provide
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

(provide bv-ranges bv-aiu? bv-parent)

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
 (list "block-edit"))

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

(provide bv-clamp! bv-follow bv-kind-line bv-multi-lit bv-place bv-plain bv-prefix bv-target bv-kids bv-width bv-command-edit bv-first-content bv-content bv-hi edit-mode edit-start edit-lo free-block lit-range top-line (struct-out bv-box))
