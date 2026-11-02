#lang racket/base
;; One job: the key menu of the live screen. It reads the key tables and draws the
;; popup of the keys that can follow, the modes box, and the float that centres it.
(require racket/list racket/string
         "../commands/commands.rkt"
         "../routes/keymaps.rkt")

;; kname answers the name of a key as shown: the space key is SPC.
(define (kname s) (if (string=? s "space") "SPC" s))

;; kseq answers a key or a sequence of keys as shown.
(define (kseq s) (string-join (map kname (sequence-of s)) " "))

;; cell-pad answers a string padded with spaces on the right to n characters.
(define (cell-pad s n)
  (string-append s (make-string (max 0 (- n (string-length s))) #\space)))

;; grid answers the lines of a titled table: a top edge with the title, a header
;; row, a line under it, one line for each row and a bottom edge, with a line
;; between every column.
(define (grid title headers rows)
  (define n (length headers))
  (define base
    (for/list ([i (in-range n)])
      (apply max (map (lambda (r) (string-length (list-ref r i))) (cons headers rows)))))
  (define head (string-append "╭─ " title " "))
  (define raw-total (+ (apply + (map (lambda (w) (+ w 2)) base)) n 1))
  (define extra (max 0 (- (+ (string-length head) 1) raw-total)))
  (define ws (append (take base (sub1 n)) (list (+ (last base) extra))))
  (define total (+ (apply + (map (lambda (w) (+ w 2)) ws)) n 1))
  (define (line l m r)
    (string-append l (string-join (map (lambda (w) (make-string (+ w 2) #\─)) ws) m) r))
  (define (row cells)
    (string-append "│"
                   (string-join (for/list ([c (in-list cells)] [w (in-list ws)])
                                  (string-append " " (cell-pad c w) " "))
                                "│")
                   "│"))
  (define top (string-append head (make-string (- total (string-length head) 1) #\─) "╮"))
  (append (list top (row headers) (line "├" "┼" "┤"))
          (map row rows)
          (list (line "╰" "┴" "╯"))))

;; enter-key answers the key of the visual layer that enters a layer: the key whose
;; command name ends with the layer name and -mode. A dash when there is none.
(define (enter-key l)
  (define hit
    (for/first ([b (in-list (keys-of "visual"))]
                #:when (string-suffix? (cadr b) (string-append l "-mode")))
      b))
  (if hit (kseq (car hit)) "-"))

;; menu-text answers the popup: table 1 holds the keys of the active layer that can
;; follow the pending keys, two key and command pairs to a row; table 2 holds every
;; mode with the key that enters it and its trigger. All of it is read from the key
;; tables, nothing is written by hand.
(define (menu-text layer pending width)
  (define following
    (for/list ([b (in-list (keys-of layer))]
               #:when (let ([s (sequence-of (car b))])
                        (and (> (length s) (length pending))
                             (equal? (take s (length pending)) pending))))
      (cons (string-join (map kname (drop (sequence-of (car b)) (length pending))) " ")
            (cadr b))))
  (define reachable
    (for/list ([l (in-list editor-layers)] #:when (not (string=? (enter-key l) "-"))) l))
  (define switch-to (filter (lambda (l) (not (string=? l layer))) reachable))
  (define mode-rows (menu-mode-rows switch-to width))
  (define shown
    (filter (lambda (p) (not (menu-mode-key? (cdr p) reachable))) following))
  (define key-width (apply max (cons 1 (map (lambda (p) (string-length (car p))) shown))))
  (define names (remove-duplicates (map (lambda (p) (menu-group-of (cdr p))) shown)))
  (define ordered (sort names < #:key menu-group-rank))
  (define group-boxes
    (append*
     (for/list ([g (in-list ordered)])
       (define cells
         (for/list ([p (in-list shown)] #:when (string=? (menu-group-of (cdr p)) g))
           (string-append (cell-pad (car p) key-width) "  " (menu-label-of (cdr p)))))
       (menu-box g (menu-cells cells (- width 8)) (- width 4)))))
  (define pick-cells
    (for/list ([b (in-list (keys-of "visual"))] #:when (and (regexp-match? #rx"^kind-" (cadr b)) (not (regexp-match? #rx" " (car b)))))
      (string-append (car b) "  " (menu-label-of (cadr b)))))
  (define pick-boxes
    (if (string=? layer "visual") (menu-box "pick · h t move between" (menu-cells pick-cells (- width 8)) (- width 4)) null))
  (define after     (if (null? pending) "keys" (format "keys after ~a" (string-join (map kname pending) " "))))
  (string-join
   (append (menu-table "modes · switch to" (car mode-rows) (cdr mode-rows) width)
           (menu-box (format "~a [~a] · ~a" (mode-label layer) (unbox kind-filter) after) (append pick-boxes group-boxes) width))
   "\n"))

;; menu-groups is the table of the menu: each command with the group box it sits in and the words it shows.
(define menu-groups
  (list (list "save" "file" "save") (list "quit" "file" "quit") (list "send" "file" "send")
        (list "check" "file" "check")
        (list "undo-mode" "view" "undo tree") (list "level-up" "page" "more rows")
        (list "next-block" "blocks" "next")
        (list "block-end" "blocks" "block end") (list "blocks" "blocks" "list")
        (list "focus-toggle" "view" "focus") (list "explorer" "view" "explorer")
        (list "block-up" "move" "block up") (list "view-up" "move" "view up") (list "view-down" "move" "view down") (list "pin-mode" "view" "pin-mode") (list "pin-add" "view" "pin-add") (list "pin-delete" "view" "pin-delete") (list "pin-next" "view" "pin-next") (list "pin-prev" "view" "pin-prev") (list "pin-top" "view" "pin-top") (list "pin-bottom" "view" "pin-bottom") (list "pin-hide" "view" "pin-hide") (list "pin-keep" "view" "pin-keep") (list "pin-earlier" "view" "pin-earlier") (list "pin-later" "view" "pin-later") (list "block-down" "move" "block down")
        (list "move-left" "move" "left") (list "move-right" "move" "right")
        (list "move-up" "move" "up") (list "move-down" "move" "down")
        (list "block-move-up" "move" "move block up") (list "block-move-down" "move" "move block down")
        (list "block-edit" "edit" "edit raw") (list "block-text" "edit" "edit text")
        (list "delete" "edit" "backspace")
        (list "kind-any" "kind" "any block") (list "kind-paragraph" "kind" "paragraph")
        (list "kind-section" "kind" "section") (list "kind-code" "kind" "code")
        (list "kind-comment" "kind" "comment") (list "kind-title" "kind" "title")
        (list "kind-todo" "todo" "any todo") (list "kind-todo-open" "todo" "open todo")
        (list "kind-todo-done" "todo" "done todo")
        (list "tab-prev" "go" "tab before") (list "tab-next" "go" "tab after")
        (list "tab-open" "go" "open next page") (list "tab-close" "go" "close tab")
        (list "bar-place-next" "place" "next place") (list "bar-bottom" "place" "bottom")
        (list "bar-top" "place" "top") (list "bar-left" "place" "left")
        (list "bar-right" "place" "right") (list "bar-sides" "place" "sides")
        (list "tab-place-next" "place" "other place") (list "tab-top" "place" "top")
        (list "tab-bottom" "place" "bottom") (list "tab-join" "place" "share edge")
        (list "bar-style" "style" "docked or floating") (list "bar-hide" "style" "hide or show")
        (list "tab-hide" "style" "hide or show")
        (list "bar-less" "level" "hide one part") (list "bar-more" "level" "show one part")
        (list "tab-less" "level" "hide one level") (list "tab-more" "level" "show one level")
        (list "bar-level-mode" "level" "level adjuster") (list "tab-level-mode" "level" "level adjuster")
        (list "cursor-mode" "view" "cursors") (list "cur-leave" "cursor" "back") (list "cur-below" "cursor" "line below")
        (list "cur-above" "cursor" "line above") (list "cur-next-block" "cursor" "next block") (list "cur-prev-block" "cursor" "block before")
        (list "cur-next-match" "cursor" "next match") (list "cur-all-matches" "cursor" "all matches")
        (list "cur-drop" "cursor" "drop last") (list "cur-clear" "cursor" "clear")
        (list "sel-left" "select" "left") (list "sel-right" "select" "right") (list "sel-up" "select" "up")
        (list "sel-down" "select" "down") (list "sel-word" "select" "word") (list "sel-word-back" "select" "word back")
        (list "sel-block-forward" "select" "block after") (list "sel-block-back" "select" "block before")
        (list "sel-next-match" "select" "next match") (list "sel-all-matches" "select" "all matches")
        (list "sel-drop" "select" "drop last") (list "sel-cancel" "select" "drop selection")
        (list "copy" "edit" "copy") (list "cut" "edit" "cut") (list "paste" "edit" "paste")
        (list "undo-back" "undo" "back") (list "undo-forward" "undo" "forward")
        (list "undo-up" "undo" "branch above") (list "undo-down" "undo" "branch below")
        (list "undo-branch-back" "undo" "last branch point") (list "undo-branch-forward" "undo" "next branch point")
        (list "undo-tip" "undo" "branch end") (list "undo-mark" "undo" "mark") (list "undo-unmark" "undo" "unmark")
        (list "undo-diff" "undo" "diff") (list "undo-live" "undo" "live file") (list "undo-keep" "undo" "keep")
        (list "undo-cancel" "undo" "roll back")
        (list "leave-write" "leave" "save and leave") (list "mode" "leave" "other layer")))

;; menu-group-order is the order of the group boxes; a group not named here comes last.
(define menu-group-order
  (list "file" "page" "blocks" "view" "move" "edit" "kind" "todo" "go" "place" "style" "level" "keys" "leave"))

;; menu-group-of answers the group box of a command; a command not in the table sits in keys.
(define (menu-group-of cmd)
  (let ([e (assoc cmd menu-groups)]) (if e (cadr e) "keys")))

;; menu-label-of answers the words shown for a command; a command not in the table shows its own name.
(define (menu-label-of cmd)
  (let ([e (assoc cmd menu-groups)]) (if e (caddr e) cmd)))

;; menu-group-rank answers the place of a group box in the order.
(define (menu-group-rank g)
  (let ([i (index-of menu-group-order g)]) (or i (length menu-group-order))))

;; menu-mode-key? asks whether a command enters one of the layers of the modes box, so its key shows there and not in the keys.
(define (menu-mode-key? cmd layers)
  (for/or ([l (in-list layers)]) (string-suffix? cmd (string-append l "-mode"))))

;; menu-box draws lines inside a box of the given total width, with the title on the top edge.
(define (menu-box title lines width)
  (define inner (- width 4))
  (define head (string-append "╭─ " title " "))
  (define top (string-append head (make-string (max 0 (- width (string-length head) 1)) #\─) "╮"))
  (append (list top)
          (for/list ([l (in-list lines)]) (string-append "│ " (cell-pad l inner) " │"))
          (list (string-append "╰" (make-string (- width 2) #\─) "╯"))))

;; menu-mode-rows answers the headers and the rows of the modes table: one row for each mode with its key, or two modes side by side when the screen is wide enough. The first half of the modes stands on the left.
(define (menu-mode-rows layers width)
  (define pairs (map (lambda (l) (list l (enter-key l))) layers))
  (define name-w (apply max (cons 4 (map (lambda (p) (string-length (car p))) pairs))))
  (define key-w (apply max (cons 3 (map (lambda (p) (string-length (cadr p))) pairs))))
  (define two? (and (> (length pairs) 1) (>= (- width 1) (* 2 (+ name-w key-w 6)))))
  (cond
    [two?
     (define rows-n (quotient (+ (length pairs) 1) 2))
     (define left (take pairs rows-n))
     (define right (drop pairs rows-n))
     (cons (list "mode" "key" "mode" "key")
           (for/list ([i (in-range rows-n)])
             (append (list-ref left i)
                     (if (< i (length right)) (list-ref right i) (list "" "")))))]
    [else (cons (list "mode" "key") pairs)]))

;; menu-table draws a table with a ruled line between every column and a header row, as wide as the given width. The spare width goes to the mode columns.
(define (menu-table title headers rows width)
  (define n (length headers))
  (define natural
    (for/list ([i (in-range n)])
      (apply max (map (lambda (r) (string-length (list-ref r i))) (cons headers rows)))))
  (define extra (max 0 (- width (+ (apply + natural) (* 3 n) 1))))
  (define name-cols (quotient (+ n 1) 2))
  (define ws
    (for/list ([w (in-list natural)] [i (in-naturals)])
      (if (even? i)
          (+ w (quotient extra name-cols) (if (< (quotient i 2) (remainder extra name-cols)) 1 0))
          w)))
  (define total (+ (apply + ws) (* 3 n) 1))
  (define (line l m r)
    (string-append l (string-join (map (lambda (w) (make-string (+ w 2) #\─)) ws) m) r))
  (define (row cells)
    (string-append "│"
                   (string-join (for/list ([c (in-list cells)] [w (in-list ws)])
                                  (string-append " " (cell-pad c w) " "))
                                "│")
                   "│"))
  (define head (string-append "╭─ " title " "))
  (define top (string-append head (make-string (max 0 (- total (string-length head) 1)) #\─) "╮"))
  (append (list top (row headers) (line "├" "┼" "┤"))
          (map row rows)
          (list (line "╰" "┴" "╯"))))

;; menu-float centers the lines of a menu in a screen of the given width by putting spaces in front of every line.
(define (menu-float text width)
  (define ls (string-split text "\n" #:trim? #f))
  (define widest (apply max (cons 0 (map string-length ls))))
  (define pad (make-string (max 0 (quotient (- width widest) 2)) #\space))
  (string-join (map (lambda (l) (string-append pad l)) ls) "\n"))

;; menu-screen answers the screen text and the point for an open menu: blank rows with the menu in the middle of the rows shown, and the point at the start of the menu so nothing scrolls.
(define (menu-screen menu top height)
  (define ms (string-split menu "\n" #:trim? #f))
  (define visible (max 1 (- height 1)))
  (define n (min (length ms) visible))
  (define before (quotient (- visible n) 2))
  (define lead (max 0 (sub1 top)))
  (define (blank k) (for/list ([i (in-range k)]) ""))
  (cons (string-join (append (blank lead) (blank before) (take ms n) (blank (- visible n before))) "\n")
        (+ lead before)))

;; menu-cells lays cells out in rows of equal columns that fit the inner width.
(define (menu-cells cells inner)
  (define cw (+ 2 (apply max (cons 1 (map string-length cells)))))
  (define per (max 1 (quotient (+ inner 2) cw)))
  (let loop ([cs cells])
    (cond
      [(null? cs) null]
      [else
       (define n (min per (length cs)))
       (cons (string-trim (string-join (for/list ([c (in-list (take cs n))]) (cell-pad c cw)) "") #:left? #f)
             (loop (drop cs n)))])))


;; Every definition above is given to the live screen.
(provide kname kseq cell-pad grid enter-key menu-text menu-groups menu-group-order menu-group-of menu-label-of menu-group-rank menu-mode-key? menu-box menu-mode-rows menu-table menu-float menu-screen menu-cells)
