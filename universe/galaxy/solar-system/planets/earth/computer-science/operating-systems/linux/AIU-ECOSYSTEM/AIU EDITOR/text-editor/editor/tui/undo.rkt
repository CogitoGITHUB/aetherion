#lang racket/base
;; undo.rkt: the undo layer, drawn like vundo. The nodes of the tree are the commits of the branch
;; aiu-undo that touch the open file; a node with more than one child is a branch point. Moving in the
;; tree shows that version in the page at once. k keeps the version, escape rolls back, l goes back to
;; the live text (to paste) and remembers the node and the point, so the next space u comes back there.
;; Loaded on first use through the stubs at the end of bar.rkt. Nothing here runs while typing.

(require "undo-git.rkt" "undo-tree.rkt"
         (only-in racket/string string-trim string-split)
         (only-in "../commands/commands.rkt"
                  commands ask session-text set-layer! the-point session-file unsaved move-to)
         (only-in "bar.rkt" undo-table undo-rows-hook)
         (only-in "box.rkt" edge-line rule-line body-line)
         (only-in "shadow.rkt" shadow-commit-now! shadow-key))


;; undo-active is true while the undo layer is open.
(define undo-active #f)
;; undo-file is the complete path of the file, undo-top the git folder top, undo-rel the path in the repository.
(define undo-file #f)
;; undo-top is the top folder of the git repository that holds the file.
(define undo-top #f)
;; undo-rel is the path of the file inside the git repository.
(define undo-rel #f)
;; undo-curf is the file in the git folder that holds the current node of this file.
(define undo-curf #f)
;; undo-cur is the node shown, undo-home the node the file was at when the layer opened, undo-marked the marked node.
(define undo-cur #f)
;; undo-home is the node the file was at when the layer opened.
(define undo-home #f)
;; undo-marked is the node marked with m, for the diff.
(define undo-marked #f)
;; undo-orig-text and undo-orig-point are the live text and point when the layer opened.
(define undo-orig-text "")
;; undo-orig-point is the live point when the layer opened.
(define undo-orig-point 0)
;; undo-diff holds the lines of a diff while the diff view shows, else nothing.
(define undo-diff (list))
;; undo-resume remembers for each file the node and the point where l left, for the next entry.
(define undo-resume (make-hash))

;; undo-glyph answers the sign of one node: a filled circle for the node shown, a diamond for the marked one.
(define (undo-glyph id)
  (cond [(equal? id undo-cur) #\●]
        [(equal? id undo-marked) #\◆]
        [else #\○]))

;; undo-put! sets one character of the grid.
(define (undo-put! cells r x ch) (hash-set! cells (cons r x) ch))

;; undo-draw answers the grid of the tree as a hash from (row . x) to a character.
(define (undo-draw)
  (let ([cells (make-hash)])
    (for ([(id p) (in-hash undo-pos)])
      (let* ([r (cdr p)] [x (* 3 (car p))] [ks (hash-ref undo-kids id (list))])
        (undo-put! cells r x (undo-glyph id))
        (when (pair? ks)
          (undo-put! cells r (+ x 1) #\─)
          (undo-put! cells r (+ x 2) #\─)
          (when (pair? (cdr ks))
            (let* ([later (cdr ks)]
                   [lastr (apply max (map (lambda (k) (cdr (hash-ref undo-pos k))) later))])
              (for ([rr (in-range (add1 r) lastr)]) (undo-put! cells rr (+ x 1) #\│))
              (for ([k (in-list later)])
                (let ([kr (cdr (hash-ref undo-pos k))])
                  (undo-put! cells kr (+ x 1) (if (= kr lastr) #\└ #\├))
                  (undo-put! cells kr (+ x 2) #\─))))))))
    cells))

;; undo-tree-lines answers the rows of the tree around the node shown, cut to the width of the panel.
(define (undo-tree-lines inner rows)
  (let* ([cells (undo-draw)]
         [p (hash-ref undo-pos undo-cur)]
         [total (add1 (* 3 (sub1 undo-cols-count)))]
         [x0 (if (<= total inner) 0 (max 0 (min (- (* 3 (car p)) (quotient inner 2)) (- total inner))))]
         [shown (min rows undo-rows-count)]
         [r0 (max 0 (min (- (cdr p) (quotient shown 2)) (- undo-rows-count shown)))])
    (for/list ([r (in-range r0 (+ r0 shown))])
      (list->string
       (for/list ([x (in-range x0 (+ x0 inner))])
         (hash-ref cells (cons r x) #\space))))))

;; undo-rows answers the rows of the panel at the bottom of the screen; bar.rkt asks it in every paint.
(define (undo-rows width height)
  (cond
    [(or (not undo-active) (not undo-cur) (not (hash-ref undo-pos undo-cur #f))) (list)]
    [else
     (let* ([inner (max 8 (- width 4))]
            [n (hash-ref undo-nodes undo-cur)]
            [idx (add1 (or (undo-index undo-cur undo-order) 0))]
            [title (undo-cut (format "undo ~a/~a~a  ~a" idx (length undo-order)
                                   (if (equal? undo-cur undo-home) " live" "") (undo-node-subject n))
                           (max 8 (- width 22)))]
            [stamp (string-append (if undo-marked "marked  " "") (undo-when (undo-node-time n)))]
            [top (edge-line "╭" "╮" title stamp width)]
            [bottom (rule-line "╰" "╯" width)])
       (cond
         [(pair? undo-diff)
          (append (list top)
                  (map (lambda (l) (body-line (undo-cut l inner) width)) (undo-first 8 undo-diff))
                  (list bottom))]
         [else
          (let* ([rows (max 1 (min undo-rows-count 5 (- height 12)))]
                 [tree (undo-tree-lines inner rows)])
            (append (list top)
                    (map (lambda (l) (body-line l width)) tree)
                    (list (body-line (undo-cut "h t back forward   n s branch   a w e jump   arrows move" inner) width)
                          (body-line (undo-cut "m u d mark unmark diff  y copy  l live  enter keep  esc" inner) width)
                          bottom)))]))]))

;; undo-text answers the text of a node, read from git once.
(define (undo-text id)
  (hash-ref! undo-texts id (lambda () (or (undo-git undo-top "show" (string-append id ":" undo-rel)) ""))))

;; undo-set-text! replaces the whole text of the page through the normal edit requests.
(define (undo-set-text! session text)
  (let ([n (undo-blen (session-text session))])
    (when (> n 0)
      (ask session "delete-at" (hasheq (quote at) "0" (quote count) (number->string n))))
    (when (> (string-length text) 0)
      (ask session "insert-at" (hasheq (quote at) "0" (quote text) text)))))

;; undo-go! shows a node: its text goes into the page and the point stays where it was, kept inside the text.
(define (undo-go! session id)
  (set! undo-cur id)
  (undo-set-text! session (undo-text id))
  (move-to session (min (the-point session) (undo-blen (undo-text id)))))

;; undo-read-cur answers the current node of the file as git keeps it, or false.
(define (undo-read-cur)
  (with-handlers ([void (lambda (e) #f)])
    (and undo-curf (file-exists? undo-curf)
         (let ([s (string-trim (call-with-input-file undo-curf undo-slurp))])
           (and (hash-ref undo-nodes s #f) s)))))

;; undo-start! opens the undo layer: it saves and commits unsaved work first, reads the tree, and comes back
;; to the node and point where l left, if there is one.
(define (undo-start! session)
  (let* ([file (path->string (path->complete-path (session-file session)))]
         [dir (let-values ([(base name d?) (split-path file)]) (if (path? base) (path->string base) "."))]
         [name (let-values ([(base nm d?) (split-path file)]) (path->string nm))]
         [info (undo-git dir "rev-parse" "--absolute-git-dir" "--show-toplevel" "--show-prefix")])
    (cond
      [(not info) (cons #t "undo: this file is not in a git repository")]
      [else
       (let* ([ls (regexp-split #rx"\n" info)]
              [gitdir (car ls)]
              [prefix (if (>= (length ls) 3) (caddr ls) "")])
         (set! undo-file file)
         (set! undo-top (cadr ls))
         (set! undo-rel (string-append prefix name))
         (set! undo-curf (path->string (build-path gitdir (string-append "aiu-undo-cur-" (shadow-key file)))))
         (when (unbox unsaved)
           ((hash-ref commands "save") session (list)))
         (shadow-commit-now! file)
         (undo-load-tree! undo-top undo-rel)
         (when (null? undo-order)
           (shadow-commit-now! file)
           (undo-load-tree! undo-top undo-rel))
         (cond
           [(null? undo-order) (cons #t "undo: no versions yet, save the file first")]
           [else
            (set! undo-orig-text (session-text session))
            (set! undo-orig-point (the-point session))
            (undo-layout!)
            (set! undo-home (or (undo-read-cur) (undo-newest)))
            (set! undo-cur undo-home)
            (set! undo-marked #f)
            (set! undo-diff (list))
            (let ([r (hash-ref undo-resume file #f)])
              (when (and r (hash-ref undo-nodes (car r) #f))
                (set! undo-cur (car r))
                (undo-set-text! session (undo-text (car r)))
                (move-to session (min (cdr r) (undo-blen (undo-text (car r)))))))
            (hash-remove! undo-resume file)
            (set! undo-active #t)
            (set-layer! session "undo")
            (cons #t "undo: h t move, k keep, escape back")]))])))

;; undo-back goes to the parent of the node shown.
(define (undo-back session)
  (let ([p (undo-parent-of undo-cur)])
    (cond [p (hash-set! undo-prefer p undo-cur) (undo-go! session p) (cons #t "undo: back")]
          [else (cons #t "undo: this is the oldest version")])))

;; undo-forward goes to the child that forward follows.
(define (undo-forward session)
  (let ([n (undo-next-of undo-cur)])
    (cond [n (undo-go! session n) (cons #t "undo: forward")]
          [else (cons #t "undo: this is the end of the branch")])))

;; undo-sibling moves to the branch above (step -1) or below (step 1) at a branch point.
(define (undo-sibling session step)
  (let* ([p (undo-parent-of undo-cur)]
         [sibs (if p (hash-ref undo-kids p (list)) undo-roots)]
         [i (undo-index undo-cur sibs)]
         [j (and i (+ i step))])
    (cond [(and j (>= j 0) (< j (length sibs)))
           (when p (hash-set! undo-prefer p (list-ref sibs j)))
           (undo-go! session (list-ref sibs j))
           (cons #t "undo: other branch")]
          [else (cons #t "undo: no branch there")])))

;; undo-branch-back goes back to the last branch point.
(define (undo-branch-back session)
  (let loop ([id (undo-parent-of undo-cur)])
    (cond [(not id) (cons #t "undo: no branch point before this")]
          [(> (length (hash-ref undo-kids id (list))) 1) (undo-go! session id) (cons #t "undo: branch point")]
          [else (loop (undo-parent-of id))])))

;; undo-branch-forward goes forward to the next branch point.
(define (undo-branch-forward session)
  (let loop ([id (undo-next-of undo-cur)])
    (cond [(not id) (cons #t "undo: no branch point ahead")]
          [(> (length (hash-ref undo-kids id (list))) 1) (undo-go! session id) (cons #t "undo: branch point")]
          [else (loop (undo-next-of id))])))

;; undo-tip goes forward to the end of the branch.
(define (undo-tip session)
  (let loop ([id undo-cur])
    (let ([n (undo-next-of id)])
      (cond [n (loop n)]
            [else (undo-go! session id) (cons #t "undo: end of the branch")]))))

;; undo-mark! marks the node shown for the diff.
(define (undo-mark! session) (set! undo-marked undo-cur) (cons #t "undo: marked"))

;; undo-unmark! takes the mark away.
(define (undo-unmark! session) (set! undo-marked #f) (cons #t "undo: unmarked"))

;; undo-show-diff shows the diff between the marked node, or the parent, and the node shown.
(define (undo-show-diff session)
  (let ([base (or undo-marked (undo-parent-of undo-cur))])
    (cond
      [(or (not base) (equal? base undo-cur)) (cons #t "undo: nothing to compare")]
      [else
       (let* ([out (or (undo-git undo-top "diff" "--no-ext-diff" "-U1" base undo-cur "--" undo-rel) "")]
              [lines (filter (lambda (l)
                               (and (> (string-length l) 0)
                                    (not (regexp-match? #rx"^(diff |index |--- |[+][+][+] )" l))))
                             (regexp-split #rx"\n" out))])
         (set! undo-diff (map (lambda (l) (regexp-replace* #rx"\t" l "    ")) lines))
         (cons #t (if (null? lines) "undo: no difference" "undo: diff, any key closes it")))])))

;; undo-restore! puts the live text and point back, as they were when the layer opened.
(define (undo-restore! session)
  (unless (equal? (session-text session) undo-orig-text)
    (undo-set-text! session undo-orig-text))
  (move-to session (min undo-orig-point (undo-blen undo-orig-text)))
  (set-box! unsaved #f))

;; undo-live goes to the live file to paste: the node and the point are remembered, the live text comes
;; back and the write layer opens at the old point.
(define (undo-live session)
  (hash-set! undo-resume undo-file (cons undo-cur (the-point session)))
  (undo-restore! session)
  (set! undo-active #f)
  ((hash-ref commands "write-mode") session (list))
  (cons #t "undo: live file, escape saves, space u comes back to the same node and point"))

;; undo-keep keeps the version shown: it becomes the current node and the file, and the layer closes.
(define (undo-keep session)
  (with-handlers ([void (lambda (e) (void))])
    (call-with-output-file undo-curf
      (lambda (o) (write-string undo-cur o) (newline o))
      #:exists (quote truncate)))
  ((hash-ref commands "save") session (list))
  (set! undo-active #f)
  (hash-remove! undo-resume undo-file)
  ((hash-ref commands "visual-mode") session (list))
  (cons #t "undo: version kept"))

;; undo-cancel rolls back to the live text and closes the layer.
(define (undo-cancel session)
  (undo-restore! session)
  (set! undo-active #f)
  (hash-remove! undo-resume undo-file)
  ((hash-ref commands "visual-mode") session (list))
  (cons #t "undo: rolled back"))

;; undo-reg! adds one command to the undo table. A command other than the first needs the layer open,
;; and the diff view is closed before it runs.
(define (undo-reg! name f open-needed?)
  (hash-set! undo-table name
             (lambda (session words)
               (cond [(and open-needed? (not undo-active)) (cons #t "undo: not open")]
                     [else (set! undo-diff (list)) (f session)]))))

;; The commands of the layer, added when this module is loaded.
(undo-reg! "undo-mode" undo-start! #f)
(undo-reg! "undo-back" undo-back #t)
(undo-reg! "undo-forward" undo-forward #t)
(undo-reg! "undo-up" (lambda (s) (undo-sibling s -1)) #t)
(undo-reg! "undo-down" (lambda (s) (undo-sibling s 1)) #t)
(undo-reg! "undo-branch-back" undo-branch-back #t)
(undo-reg! "undo-branch-forward" undo-branch-forward #t)
(undo-reg! "undo-tip" undo-tip #t)
(undo-reg! "undo-mark" undo-mark! #t)
(undo-reg! "undo-unmark" undo-unmark! #t)
(undo-reg! "undo-diff" undo-show-diff #t)
(undo-reg! "undo-live" undo-live #t)
(undo-reg! "undo-keep" undo-keep #t)
(undo-reg! "undo-cancel" undo-cancel #t)
(set-box! undo-rows-hook undo-rows)
