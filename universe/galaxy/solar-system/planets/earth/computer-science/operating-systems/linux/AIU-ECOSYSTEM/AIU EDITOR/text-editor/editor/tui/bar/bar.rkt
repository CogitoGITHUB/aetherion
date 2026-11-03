#lang racket/base

(require racket/list
         racket/string
         racket/path
         "../../commands/commands.rkt"
         "../../commands/lazy-stub.rkt"
         "../../routes/keymaps.rkt"
         "../float/box.rkt"
         "../tabs/tabs.rkt"
         "bar-clock.rkt"
         "bar-git.rkt"
         "bar-state.rkt"
         "bar-rows.rkt"
         "bar-commands.rkt")

(struct bar-plan (left right top bottom text overlay line?) #:transparent)

(define (bar-plan-of session pending width height again)
  (define layer (the-layer session))
  (define file (session-file session))
  (define short (let ([n (file-name-from-path file)]) (if n (path->string n) (path->string file))))
  (define dir (path->string (or (path-only (path->complete-path file)) (current-directory))))
  (define want (unbox bar-place))
  (define place (if (and (member want (list "bottom" "top")) (< height 14)) "line" want))
  (define names (take bar-order (min (length bar-order) (max 0 (unbox bar-count)))))
  (define tabs-on?
    (and (>= height 16) (not (string=? (unbox tab-place) "hidden"))))
  (cond
    [(unbox focus-on) (bar-plan 0 0 0 0 "" "" #f)]
    [else
     (unless (or (unbox unsaved) (member place (list "line" "hidden"))) (git-refresh-maybe dir again))
     (define g (unbox git-info))
     (define undo-lines (if (string=? layer "undo") ((unbox undo-rows-hook) width height) null))
     (define bar-lines
       (if (member place (list "bottom" "top")) (let ([r (bar-rows layer short pending g width names)]) (if (> (length r) (- height 4)) (take r (- height 4)) r)) null))
     (define tab-lines
       (if (and tabs-on? (<= (length bar-lines) 8)) (tab-rows (path->string (path->complete-path file)) width again) null))
     (define (group where)
       (define t (if (and tabs-on? (string=? (unbox tab-place) where)) tab-lines null))
       (define b (if (string=? place where) bar-lines null))
       (cond [(and (pair? t) (pair? b) (unbox tab-joined))
              (append (drop-right t 1) (list (join-edge (car b))) (cdr b))]
             [else (append t b)]))
     (define top-lines (if (unbox split-panes-on) (group "top") (append (group "top") (unbox title-rows) (list (rule-line "╭" "╮" width)))))
     (define bottom-lines (let ([g0 (if (pair? undo-lines) undo-lines (group "bottom"))]) (if (and (null? undo-lines) (string=? place "line")) g0 (if (unbox split-panes-on) g0 (cons (rule-line "╰" "╯" width) g0)))))
     (define top-n (length top-lines))
     (define sh (max 3 (- height top-n (length bottom-lines))))
     (define left-names
       (cond [(string=? place "left") names]
             [(string=? place "sides") (filter (lambda (n) (or (member n (list "mode" "keys")) (and (string=? n "save") (unbox unsaved)))) names)]
             [else null]))
     (define right-names
       (cond [(string=? place "right") names]
             [(string=? place "sides") (filter (lambda (n) (member n (list "time" "date"))) names)]
             [else null]))
     (define docked?
       (and (string=? (unbox bar-style) "docked")
            (>= (- width (if (null? left-names) 0 5) (if (null? right-names) 0 5)) 20)))
     (define lines-l (strip-lines left-names layer g sh docked?))
     (define lines-r (strip-lines right-names layer g sh docked?))
     (define drawn
       (string-append (draw-at top-lines 1 1)
                      (if (null? lines-l) "" (draw-at lines-l (+ top-n 1) 1))
                      (if (null? lines-r) "" (draw-at lines-r (+ top-n 1) (max 1 (- width 4))))
                      (if (and (null? lines-l) (not (unbox split-panes-on))) (draw-at (for/list ([i (in-range sh)]) "│") (+ top-n 1) 1) "")
                      (if (and (null? lines-r) (not (unbox split-panes-on))) (draw-at (for/list ([i (in-range sh)]) "│") (+ top-n 1) width) "")))
     (define line? (and (string=? place "line") (null? undo-lines)))
     (bar-plan (cond [(and docked? (pair? lines-l)) 5] [(null? lines-l) (if (unbox split-panes-on) 0 1)] [else 0])
               (cond [(and docked? (pair? lines-r)) 5] [(null? lines-r) (if (unbox split-panes-on) 0 1)] [else 0])
               top-n
               (if line? 1 (length bottom-lines))
               (string-join bottom-lines "\n")
               (if (string=? drawn "") "" (white drawn))
               line?)]))

(provide git-stale! (struct-out bar-plan)
         bar-plan-of)

(define undo-table
  (lazy-layer! (#%variable-reference) "../undo/undo.rkt" "undo" "undo is not available"
               (list "undo-mode" "undo-back" "undo-forward" "undo-up" "undo-down"
                     "undo-branch-back" "undo-branch-forward" "undo-tip" "undo-mark"
                     "undo-unmark" "undo-diff" "undo-live" "undo-keep" "undo-cancel")))

(define undo-rows-hook (box (lambda (width height) null)))

(define multi-table
  (lazy-layer! (#%variable-reference) "../multi/multi.rkt" "cursors" "cursors are not available"
               (list "cursor-mode" "cur-leave" "cur-below" "cur-above" "cur-next-block" "cur-prev-block"
                     "cur-next-match" "cur-all-matches" "cur-drop" "cur-clear" "select-mode"
                     "sel-left" "sel-right" "sel-up" "sel-down" "sel-word" "sel-word-back"
                     "sel-block-forward" "sel-block-back" "sel-next-match" "sel-all-matches"
                     "sel-drop" "sel-cancel")))

(define clip-table
  (lazy-layer! (#%variable-reference) "../text/clip.rkt" "clip" "copy and paste are not available"
               (list "copy" "cut" "paste")))

(provide undo-table undo-rows-hook multi-table clip-table)
