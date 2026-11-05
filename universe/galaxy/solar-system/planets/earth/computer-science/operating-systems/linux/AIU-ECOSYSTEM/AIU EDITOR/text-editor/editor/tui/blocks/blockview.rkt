#lang racket/base

(require racket/list
         racket/string
         "../../commands/commands-shared.rkt"
         "../../machine/terminal.rkt"
         "../../bridge/document-shared.rkt"
         "../../bridge/host-shared.rkt"
         "../float/pins.rkt" "blocks-kind.rkt" "blockview-boxes.rkt")

(define edit-start (box #f))

(define edit-mode (box "raw"))

(define edit-lo (box 0))

(define top-line (box 1))

(define view-cache (box #f))

(define (drawn-view session raw width)
  (define hit (unbox view-cache))
  (if (and hit (equal? (car hit) raw) (equal? (cadr hit) width))
      (caddr hit)
      (let ([drawn (view-of (session-file session) (session-journal session) width)])
        (set-box! view-cache (list raw width drawn))
        drawn)))

(define (blockview-aiu? session)
  (string-suffix? (path->string (session-file session)) ".aiu"))

(define (blockview-width)
  (let-values ([(w h) (terminal-size)])
    w))

(define (blockview-light line)
  (string-append "\u001b[7m"
                 (regexp-replace* #px"\u001b\\[0?m" line "\u001b[0m\u001b[7m")
                 "\u001b[0m"))

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

(define lit-range (box #f))

(define free-block (box #f))

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

(define (blockview-kind-line got target range i)
  (if (and (> (car range) 0) (= i (- (car range) 1)))
      (let ([chain (let loop ([b target] [acc (list)])
                     (if b (loop (blockview-parent (page-blocks got) b) (cons (block-name b) acc)) acc))])
        (string-append "\u001b[90m" (string-join chain " > ") "\u001b[0m"))
      ""))
(define (blockview-command-view-up session words)
  (set-box! top-line (max 1 (- (unbox top-line) 3)))
  (set-box! free-block #t)
  (cons #t "view up"))

(define (blockview-command-view-down session words)
  (set-box! top-line (+ (unbox top-line) 3))
  (set-box! free-block #t)
  (cons #t "view down"))

(define (blockview-command-view-page-up session words)
  (cond
    [(blockview-aiu? session)
     (set-box! top-line (max 1 (- (unbox top-line) 12)))
     (set-box! free-block #t)]
    [else (set-view-top! session (- (the-view-top session) 12))])
  (cons #t "view page up"))

(define (blockview-command-view-page-down session words)
  (cond
    [(blockview-aiu? session)
     (set-box! top-line (+ (unbox top-line) 12))
     (set-box! free-block #t)]
    [else (set-view-top! session (+ (the-view-top session) 12))])
  (cons #t "view page down"))

(define (blockview-center from to visible)
  (define next (if (>= (- to from) visible) from (max 1 (- (quotient (+ from to) 2) (quotient visible 2)))))
  (set-box! top-line next)
  next)

(define (blockview-command-leave-write session words)
  ((hash-ref commands "save") session words)
  (set-layer! session "visual")
  (cons #t "saved"))

(define (blockview-near . parts)
  (let ([src (variable-reference->module-source (#%variable-reference))])
    (and (path? src)
         (let-values ([(base file dir?) (split-path src)])
           (and (path? base) (simplify-path (apply build-path base parts)))))))

(define (blockview-after-write file)
  (with-handlers ([void void])
    (let ([hp (blockview-near (quote up) (quote up) "join" "hot-path.rkt")])
      (when hp ((unbox (dynamic-require hp (quote edit-hook))))))
    (let ([sh (blockview-near "../float/shadow.rkt")])
      (when (and sh file)
        (thread (lambda ()
                  (with-handlers ([void void])
                    ((dynamic-require sh (quote shadow-note!)) file))))))))

(hash-set! commands "view-up" blockview-command-view-up)
(hash-set! commands "view-down" blockview-command-view-down)
(hash-set! commands "view-page-up" blockview-command-view-page-up)
(hash-set! commands "view-page-down" blockview-command-view-page-down)
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

(provide
         drawn-view)

(define (blockview-todo-state b)
  (define found
    (filter (lambda (d) (member (decl-keyword d) (list "todo" "todo:")))
            (block-decls b)))
  (cond
    [(null? found) #f]
    [else
     (define words (string-split (format "~a" (decl-value (car found)))))
     (if (and (pair? words) (string=? (car words) "done")) "done" "open")]))

(define (blockview-kind-match? b)
  (define want (unbox kind-filter))
  (cond
    [(string=? want "any") #t]
    [(string=? want "todo") (and (blockview-todo-state b) #t)]
    [(string=? want "todo open") (equal? (blockview-todo-state b) "open")]
    [(string=? want "todo done") (equal? (blockview-todo-state b) "done")]
    [else (string=? (block-name b) want)]))

(provide blockview-ranges blockview-aiu? blockview-parent)

(hash-set! commands "save"
           (let ([orig (hash-ref commands "save")])
             (lambda (session words)
               (let ([r (orig session words)])
                 (set-box! unsaved #f)
                 (blockview-after-write (session-file session))
                 r))))

(define blockview-multi-cache (box #f))

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


(hash-set! commands "visual-mode"
           (let ([orig (hash-ref commands "visual-mode")])
             (lambda (session words)
               (if (and (string=? (the-layer session) "visual") (multi-live? session))
                   (begin (multi-clear!) (cons #t "cursors cleared"))
                   (orig session words)))))

(provide blockview-kind-match? blockview-inside blockview-drawn)

(hash-set! commands "leave-write"
           (let ([orig (hash-ref commands "leave-write")])
             (lambda (session words)
               (let ([r (orig session words)])
                 (multi-drop-selections!)
                 r))))

(provide blockview-follow blockview-kind-line blockview-multi-lit blockview-place blockview-plain blockview-prefix blockview-target blockview-kids blockview-width edit-mode edit-start edit-lo free-block lit-range top-line (struct-out blockview-box))
