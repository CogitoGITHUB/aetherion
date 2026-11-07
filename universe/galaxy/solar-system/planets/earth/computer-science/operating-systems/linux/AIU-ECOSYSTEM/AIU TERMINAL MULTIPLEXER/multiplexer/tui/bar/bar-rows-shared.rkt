#lang racket/base
(require racket/list
         racket/string
         racket/path
         "../../commands/commands-shared.rkt"
         "../../commands/lazy-stub-shared.rkt"
         "../../routes/keymaps-shared.rkt"
         "../float/box-shared.rkt" (only-in "bar-menu-shared.rkt" menu-label-of menu-text)
         "../tabs/tabs-shared.rkt"
         "bar-clock-shared.rkt"
         "bar-git-shared.rkt"
         "bar-state-shared.rkt")


(define (layer-keys-line layer width)
  (define names (remove-duplicates (for/list ([b (in-list (keys-of layer))]) (string-append (string-join (map bar-kname (sequence-of (car b))) " ") " " (menu-label-of (cadr b))))))
  (define all (string-join names "  "))
  (define room (max 1 width))
  (if (> (string-length all) room) (string-append (substring all 0 (max 0 (- room 1))) "…") all))

(define (layer-key-rows layer width)
  (define names (remove-duplicates (for/list ([b (in-list (keys-of layer))]) (string-append (string-join (map bar-kname (sequence-of (car b))) " ") " " (menu-label-of (cadr b))))))
  (let loop ([rest names] [row ""] [acc null])
    (cond [(null? rest) (reverse (if (string=? row "") acc (cons row acc)))]
          [(string=? row "") (loop (cdr rest) (car rest) acc)]
          [(> (+ (string-length row) 2 (string-length (car rest))) width) (loop rest "" (cons row acc))]
          [else (loop (cdr rest) (string-append row "  " (car rest)) acc)])))

(define (bar-rows layer short pending g width names)
  (define p (unbox name-prompt))
  (if p
      (list (edge-line "╭" "╮" "name" "" width)
            (body-line (format "name for the new ~a: ~a▏" (car p) (cadr p)) width)
            (body-line (format "return creates   escape cancels   ~a" (cadddr p)) width)
            (rule-line "╰" "╯" width))
      (bar-rows-plain layer short pending g width names)))

(define (bar-rows-plain layer short pending g width names)
  (define (has? n) (member n names))
  (define trig (let ([t (assoc layer trigger-of)]) (if t (cdr t) "-")))
  (define waiting
    (if (pair? pending) (format "  waiting after ~a" (string-join (map bar-kname pending) " ")) ""))
  (define title (if (has? "mode") (format "~a [~a] · ~a" (mode-label layer) (unbox kind-filter) (if (getenv "AIU_PANE_PROGRAM") "aiu shell" short)) "bar"))
  (define stamp
    "")
  (define middle
    (append (if (has? "keys")
                (if (or (pair? pending) (unbox menu-pinned) (not (member layer (list "visual" "write")))) (map (lambda (r) (body-line r width)) (let ([ls (string-split (menu-text layer pending (max 20 (- width 4))) "\n" #:trim? #f)]) ls)) (list (body-line (format "trigger ~a~a  ·  press ~a for keys" (bar-kname trig) waiting (bar-kname trig)) width)))
                null)
            (if (and (has? "save") (unbox unsaved))
                (list (edge-line "├" "┤" "save" "" width) (body-line "unsaved  SPC s saves" width))
                null)))
  (if (null? names)
      null
      (append (list (edge-line "╭" "╮" title stamp width)) middle (list (clock-rule-line "╰" "╯" width (and (has? "time") #t) (and (has? "date") #t))))))

(define (keys-body-rows layer pending width)
  (define trig (let ([t (assoc layer trigger-of)]) (if t (cdr t) "-")))
  (define waiting
    (if (pair? pending) (format "  waiting after ~a" (string-join (map bar-kname pending) " ")) ""))
  (if (or (pair? pending) (unbox menu-pinned) (not (member layer (list "visual" "write"))))
      (map (lambda (r) (body-line r width)) (string-split (menu-text layer pending (max 20 (- width 4))) "\n" #:trim? #f))
      (list (body-line (format "trigger ~a~a  ·  press ~a for keys" (bar-kname trig) waiting (bar-kname trig)) width))))

(define (cell-chars name layer g)
  (cond
    [(string=? name "mode") (format "~a ~a" (mode-label layer) (unbox kind-filter))]
    [(string=? name "time") (clock-time)]
    [(string=? name "date") (clock-date)]
    [(string=? name "save") "SAVE"]
    [else (let ([t (assoc layer trigger-of)]) (bar-kname (if t (cdr t) "-")))]))

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


(provide layer-keys-line bar-rows cell-chars strip-lines keys-body-rows)
