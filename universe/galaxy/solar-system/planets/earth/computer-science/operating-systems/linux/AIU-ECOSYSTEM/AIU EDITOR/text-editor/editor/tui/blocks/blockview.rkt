#lang racket/base
;; One job: the block cursor and the block edit of a page in the live session.
;; In the view layer the block under the point is lit. The keys up and down move
;; the point from block to block, the key i edits only its text inside its box, and the key w opens only that block as raw
;; text while every other block stays drawn. Nothing here edits text: the edit
;; is the write layer, kept inside one block.

(require racket/list
         racket/string
         "../../commands/commands.rkt"
         "../../machine/terminal.rkt"
         "../../notation/document.rkt"
         "../../notation/host.rkt"
         "../pins.rkt" "blocks-kind.rkt" "blockview-boxes.rkt")

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

;; blockview-aiu? answers whether the session edits a page of the notation.
(define (blockview-aiu? session)
  (string-suffix? (path->string (session-file session)) ".aiu"))

;; blockview-width answers the width of the terminal, the width the screen draws at.
(define (blockview-width)
  (let-values ([(w h) (terminal-size)])
    w))

;; blockview-light answers a line in reverse video. The line may carry colours of its
;; own, so reverse video is put back after each reset.
(define (blockview-light line)
  (string-append "\u001b[7m"
                 (regexp-replace* #px"\u001b\\[0?m" line "\u001b[0m\u001b[7m")
                 "\u001b[0m"))

;; blockview-follow answers the first line to show so that the lines from to to are in
;; the window. A block taller than the window shows from its first line.
(define (blockview-follow from to visible)
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

;; blockview-place answers the first line to show: after a scroll key the view stays where it was moved but the lit block stays on screen, otherwise the block is centred.
(define (blockview-place from to visible)
  (define fbv (unbox free-block))
  (set-box! lit-range (cons from to))
  (cond
    [(and fbv (or (eq? fbv #t) (eqv? fbv from)))
     (set-box! free-block from)
     (let* ([lo (max 1 (+ (- to visible) 1))]
            [next (max 1 (unbox top-line))])
       (set-box! top-line next)
       next)]
    [else (set-box! free-block #f) (blockview-center from to visible)]))

;; blockview-kind-line answers the line shown in focus mode: the box types from the page top down to the lit box in grey on the line above it, and an empty line elsewhere.
(define (blockview-kind-line got target range i)
  (if (and (> (car range) 0) (= i (- (car range) 1)))
      (let ([chain (let loop ([b target] [acc (list)])
                     (if b (loop (blockview-parent (page-blocks got) b) (cons (block-name b) acc)) acc))])
        (string-append "\u001b[90m" (string-join chain " > ") "\u001b[0m"))
      ""))
;; blockview-command-view-up scrolls the view up by 3 lines.
(define (blockview-command-view-up session words)
  (set-box! top-line (max 1 (- (unbox top-line) 3)))
  (set-box! free-block #t)
  (cons #t "view up"))

;; blockview-command-view-down scrolls the view down by 3 lines.
(define (blockview-command-view-down session words)
  (set-box! top-line (+ (unbox top-line) 3))
  (set-box! free-block #t)
  (cons #t "view down"))

;; blockview-center answers the first line to show so that the lines from to to sit in the middle of the window; a block taller than the window shows from its first line.
(define (blockview-center from to visible)
  (define next (if (>= (- to from) visible) from (max 1 (- (quotient (+ from to) 2) (quotient visible 2)))))
  (set-box! top-line next)
  next)

;; blockview-command-leave-write saves, then goes back to the visual layer.
(define (blockview-command-leave-write session words)
  ((hash-ref commands "save") session words)
  (set-layer! session "visual")
  (cons #t "saved"))

;; blockview-near answers the path of a module found from the folder of this one, or false.
(define (blockview-near . parts)
  (let ([src (variable-reference->module-source (#%variable-reference))])
    (and (path? src)
         (let-values ([(base file dir?) (split-path src)])
           (and (path? base) (simplify-path (apply build-path base parts)))))))

;; blockview-after-write runs once when the write layer is left: the git row and strip are marked old
;; through edit-hook, and one undo commit is noted in a thread. Nothing runs while typing.
(define (blockview-after-write file)
  (with-handlers ([void void])
    (let ([hp (blockview-near (quote up) (quote up) "join" "hot-path.rkt")])
      (when hp ((unbox (dynamic-require hp (quote edit-hook))))))
    (let ([sh (blockview-near "../shadow.rkt")])
      (when (and sh file)
        (thread (lambda ()
                  (with-handlers ([void void])
                    ((dynamic-require sh (quote shadow-note!)) file))))))))

;; The four keys are added to the command table when this module is loaded, so
;; the keys find them and the gate sees the same table the editor does.
(hash-set! commands "view-up" blockview-command-view-up)
(hash-set! commands "view-down" blockview-command-view-down)
(hash-set! commands "pin-mode" blockview-command-pin-mode)
(hash-set! commands "pin-add" blockview-command-pin-add)
(hash-set! commands "pin-delete" blockview-command-pin-delete)
(hash-set! commands "pin-next" blockview-command-pin-next)
(hash-set! commands "pin-prev" blockview-command-pin-prev)
(hash-set! commands "pin-top" blockview-command-pin-top)
(hash-set! commands "pin-bottom" blockview-command-pin-bottom)
(hash-set! commands "pin-hide" blockview-command-pin-hide)
(hash-set! commands "pin-keep" blockview-command-pin-keep)
(hash-set! commands "pin-earlier" blockview-command-pin-earlier)
(hash-set! commands "pin-later" blockview-command-pin-later)
(hash-set! commands "leave-write" (lambda (session words) (let ([r (blockview-command-leave-write session words)]) (set-box! unsaved #f) (blockview-after-write (session-file session)) r)))

;; The block view, for the live screen above it.
(provide
         drawn-view)

;; blockview-todo-state answers done or open for the todo on a block, or false when the block holds no todo. The state is the first word after todo: and no word means open.
(define (blockview-todo-state b)
  (define found
    (filter (lambda (d) (member (decl-keyword d) (list "todo" "todo:")))
            (block-decls b)))
  (cond
    [(null? found) #f]
    [else
     (define words (string-split (format "~a" (decl-value (car found)))))
     (if (and (pair? words) (string=? (car words) "done")) "done" "open")]))

;; blockview-kind-match? asks whether a block is of the kind the kind layer picked.
(define (blockview-kind-match? b)
  (define want (unbox kind-filter))
  (cond
    [(string=? want "any") #t]
    [(string=? want "todo") (and (blockview-todo-state b) #t)]
    [(string=? want "todo open") (equal? (blockview-todo-state b) "open")]
    [(string=? want "todo done") (equal? (blockview-todo-state b) "done")]
    [else (string=? (block-name b) want)]))

(provide blockview-ranges blockview-aiu? blockview-parent)

;; The save command is wrapped: it saves, clears unsaved, then runs the git refresh and one undo commit.
;; Nothing else saves or commits; typing only marks the file unsaved.
(hash-set! commands "save"
           (let ([orig (hash-ref commands "save")])
             (lambda (session words)
               (let ([r (orig session words)])
                 (set-box! unsaved #f)
                 (blockview-after-write (session-file session))
                 r))))

;; blockview-multi-cache keeps the lit ranges of the last drawing, keyed by its ranges table.
(define blockview-multi-cache (box #f))

;; blockview-multi-lit answers the line ranges the extra cursors and the selections light, besides the block at the point.
(define (blockview-multi-lit session got ranges)
  (cond
    [(not (multi-live? session)) (list)]
    [else
     (let ([c (unbox blockview-multi-cache)])
       (if (and c (eq? (car c) ranges))
           (cdr c)
           (let ([r ((unbox multi-lit-hook) got ranges (the-point session))])
             (set-box! blockview-multi-cache (cons ranges r))
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


;; Escape in the visual layer drops the extra cursors and the selections first; escape elsewhere is the old command.
(hash-set! commands "visual-mode"
           (let ([orig (hash-ref commands "visual-mode")])
             (lambda (session words)
               (if (and (string=? (the-layer session) "visual") (multi-live? session))
                   (begin (multi-clear!) (cons #t "cursors cleared"))
                   (orig session words)))))

;; The pieces multi.rkt needs from this module.
(provide blockview-kind-match? blockview-inside blockview-drawn)

;; Leaving the write layer drops the selections: the extra cursors stay, so a second round of writing can follow.
(hash-set! commands "leave-write"
           (let ([orig (hash-ref commands "leave-write")])
             (lambda (session words)
               (let ([r (orig session words)])
                 (multi-drop-selections!)
                 r))))

(provide blockview-follow blockview-kind-line blockview-multi-lit blockview-place blockview-plain blockview-prefix blockview-target blockview-kids blockview-width edit-mode edit-start edit-lo free-block lit-range top-line (struct-out blockview-box))
