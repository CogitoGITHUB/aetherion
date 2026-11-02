#lang racket/base
;; One job: the drawing of the bar rows and the side strips as lines of text.
(require racket/list
         racket/string
         racket/path
         "../commands/commands.rkt"
         "../commands/lazy-stub.rkt"
         "../routes/keymaps.rkt"
         "box.rkt"
         "tabs.rkt"
         "bar-clock.rkt"
         "bar-git.rkt"
         "bar-state.rkt")


;; layer-keys-line answers the keys of a layer as one row of key names, cut to the width.
(define (layer-keys-line layer width)
  (define names (remove-duplicates (for/list ([b (in-list (keys-of layer))]) (string-join (map bar-kname (sequence-of (car b))) " "))))
  (define all (string-join names "  "))
  (define room (max 1 width))
  (if (> (string-length all) room) (string-append (substring all 0 (max 0 (- room 1))) "…") all))

;; bar-rows answers the rows of the bar as a box of the full width: the layer and
;; the file on the top edge with the time and the date, the trigger row, and the
;; git row. A part that is not in names is left out.
(define (bar-rows layer short pending g width names)
  (define (has? n) (member n names))
  (define trig (let ([t (assoc layer trigger-of)]) (if t (cdr t) "-")))
  (define waiting
    (if (pair? pending) (format "  waiting after ~a" (string-join (map bar-kname pending) " ")) ""))
  (define title (if (has? "mode") (format "~a [~a] · ~a" (mode-label layer) (unbox kind-filter) short) "bar"))
  (define stamp
    (string-join (filter values (list (and (has? "time") (clock-time)) (and (has? "date") (clock-date)))) "  "))
  (define middle
    (append (if (has? "keys")
                (list (body-line (string-append (format "trigger ~a~a" (bar-kname trig) waiting) "  " (layer-keys-line layer (max 1 (- width 30)))) width))
                null)
            (if (and (has? "save") (unbox unsaved))
                (list (edge-line "├" "┤" "save" "" width) (body-line "unsaved  SPC s saves" width))
                null)))
  (if (null? names)
      null
      (append (list (edge-line "╭" "╮" title stamp width)) middle (list (rule-line "╰" "╯" width)))))

;; cell-chars answers the text of one part of a side strip, to be drawn one
;; letter to a row.
(define (cell-chars name layer g)
  (cond
    [(string=? name "mode") (format "~a ~a" (mode-label layer) (unbox kind-filter))]
    [(string=? name "time") (clock-time)]
    [(string=? name "date") (clock-date)]
    [(string=? name "save") "SAVE"]
    [else (let ([t (assoc layer trigger-of)]) (bar-kname (if t (cdr t) "-")))]))

;; strip-lines answers the rows of a side strip, five columns wide: one cell for
;; each part, the letters upright, a line between the cells. A docked strip runs
;; the full height it is given, a floating one is as tall as its cells.
(define (strip-lines names layer g height docked?)
  (cond
    [(null? names) null]
    [else
     (define n (length names))
     (define budget (max 1 (quotient (- height 2 (sub1 n)) n)))
     (define body
       (append*
        (for/list ([nm (in-list names)] [i (in-naturals)])
          (define chars (string->list (cell-chars nm layer g)))
          (define shown (if (> (length chars) budget) (take chars budget) chars))
          (append (if (zero? i) null (list "├───┤"))
                  (for/list ([c (in-list shown)]) (string-append "│ " (string c) " │"))))))
     (define filler
       (if docked?
           (for/list ([i (in-range (max 0 (- height 2 (length body))))]) "│   │")
           null))
     (append (list "╭───╮") body filler (list "╰───╯"))]))


(provide layer-keys-line bar-rows cell-chars strip-lines)
