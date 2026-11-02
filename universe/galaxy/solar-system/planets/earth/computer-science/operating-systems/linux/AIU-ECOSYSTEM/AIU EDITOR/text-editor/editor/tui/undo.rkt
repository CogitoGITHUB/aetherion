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


;; ud-active is true while the undo layer is open.
(define ud-active #f)
;; ud-file is the complete path of the file, ud-top the git folder top, ud-rel the path in the repository.
(define ud-file #f)
;; ud-top is the top folder of the git repository that holds the file.
(define ud-top #f)
;; ud-rel is the path of the file inside the git repository.
(define ud-rel #f)
;; ud-curf is the file in the git folder that holds the current node of this file.
(define ud-curf #f)
;; ud-cur is the node shown, ud-home the node the file was at when the layer opened, ud-mark the marked node.
(define ud-cur #f)
;; ud-home is the node the file was at when the layer opened.
(define ud-home #f)
;; ud-mark is the node marked with m, for the diff.
(define ud-mark #f)
;; ud-orig-text and ud-orig-point are the live text and point when the layer opened.
(define ud-orig-text "")
;; ud-orig-point is the live point when the layer opened.
(define ud-orig-point 0)
;; ud-diff holds the lines of a diff while the diff view shows, else nothing.
(define ud-diff (list))
;; ud-resume remembers for each file the node and the point where l left, for the next entry.
(define ud-resume (make-hash))

;; ud-glyph answers the sign of one node: a filled circle for the node shown, a diamond for the marked one.
(define (ud-glyph id)
  (cond [(equal? id ud-cur) #\●]
        [(equal? id ud-mark) #\◆]
        [else #\○]))

;; ud-put! sets one character of the grid.
(define (ud-put! cells r x ch) (hash-set! cells (cons r x) ch))

;; ud-draw answers the grid of the tree as a hash from (row . x) to a character.
(define (ud-draw)
  (let ([cells (make-hash)])
    (for ([(id p) (in-hash ud-pos)])
      (let* ([r (cdr p)] [x (* 3 (car p))] [ks (hash-ref ud-kids id (list))])
        (ud-put! cells r x (ud-glyph id))
        (when (pair? ks)
          (ud-put! cells r (+ x 1) #\─)
          (ud-put! cells r (+ x 2) #\─)
          (when (pair? (cdr ks))
            (let* ([later (cdr ks)]
                   [lastr (apply max (map (lambda (k) (cdr (hash-ref ud-pos k))) later))])
              (for ([rr (in-range (add1 r) lastr)]) (ud-put! cells rr (+ x 1) #\│))
              (for ([k (in-list later)])
                (let ([kr (cdr (hash-ref ud-pos k))])
                  (ud-put! cells kr (+ x 1) (if (= kr lastr) #\└ #\├))
                  (ud-put! cells kr (+ x 2) #\─))))))))
    cells))

;; ud-tree-lines answers the rows of the tree around the node shown, cut to the width of the panel.
(define (ud-tree-lines inner rows)
  (let* ([cells (ud-draw)]
         [p (hash-ref ud-pos ud-cur)]
         [total (add1 (* 3 (sub1 ud-cols-count)))]
         [x0 (if (<= total inner) 0 (max 0 (min (- (* 3 (car p)) (quotient inner 2)) (- total inner))))]
         [shown (min rows ud-rows-count)]
         [r0 (max 0 (min (- (cdr p) (quotient shown 2)) (- ud-rows-count shown)))])
    (for/list ([r (in-range r0 (+ r0 shown))])
      (list->string
       (for/list ([x (in-range x0 (+ x0 inner))])
         (hash-ref cells (cons r x) #\space))))))

;; ud-rows answers the rows of the panel at the bottom of the screen; bar.rkt asks it in every paint.
(define (ud-rows width height)
  (cond
    [(or (not ud-active) (not ud-cur) (not (hash-ref ud-pos ud-cur #f))) (list)]
    [else
     (let* ([inner (max 8 (- width 4))]
            [n (hash-ref ud-nodes ud-cur)]
            [idx (add1 (or (ud-index ud-cur ud-order) 0))]
            [title (ud-cut (format "undo ~a/~a~a  ~a" idx (length ud-order)
                                   (if (equal? ud-cur ud-home) " live" "") (ud-node-subject n))
                           (max 8 (- width 22)))]
            [stamp (string-append (if ud-mark "marked  " "") (ud-when (ud-node-time n)))]
            [top (edge-line "╭" "╮" title stamp width)]
            [bottom (rule-line "╰" "╯" width)])
       (cond
         [(pair? ud-diff)
          (append (list top)
                  (map (lambda (l) (body-line (ud-cut l inner) width)) (ud-first 8 ud-diff))
                  (list bottom))]
         [else
          (let* ([rows (max 1 (min ud-rows-count 5 (- height 12)))]
                 [tree (ud-tree-lines inner rows)])
            (append (list top)
                    (map (lambda (l) (body-line l width)) tree)
                    (list (body-line (ud-cut "h t back forward   n s branch   a w e jump   arrows move" inner) width)
                          (body-line (ud-cut "m u d mark unmark diff  y copy  l live  enter keep  esc" inner) width)
                          bottom)))]))]))

;; ud-text answers the text of a node, read from git once.
(define (ud-text id)
  (hash-ref! ud-texts id (lambda () (or (ud-git ud-top "show" (string-append id ":" ud-rel)) ""))))

;; ud-set-text! replaces the whole text of the page through the normal edit requests.
(define (ud-set-text! session text)
  (let ([n (ud-blen (session-text session))])
    (when (> n 0)
      (ask session "delete-at" (hasheq (quote at) "0" (quote count) (number->string n))))
    (when (> (string-length text) 0)
      (ask session "insert-at" (hasheq (quote at) "0" (quote text) text)))))

;; ud-go! shows a node: its text goes into the page and the point stays where it was, kept inside the text.
(define (ud-go! session id)
  (set! ud-cur id)
  (ud-set-text! session (ud-text id))
  (move-to session (min (the-point session) (ud-blen (ud-text id)))))

;; ud-read-cur answers the current node of the file as git keeps it, or false.
(define (ud-read-cur)
  (with-handlers ([void (lambda (e) #f)])
    (and ud-curf (file-exists? ud-curf)
         (let ([s (string-trim (call-with-input-file ud-curf ud-slurp))])
           (and (hash-ref ud-nodes s #f) s)))))

;; ud-start! opens the undo layer: it saves and commits unsaved work first, reads the tree, and comes back
;; to the node and point where l left, if there is one.
(define (ud-start! session)
  (let* ([file (path->string (path->complete-path (session-file session)))]
         [dir (let-values ([(base name d?) (split-path file)]) (if (path? base) (path->string base) "."))]
         [name (let-values ([(base nm d?) (split-path file)]) (path->string nm))]
         [info (ud-git dir "rev-parse" "--absolute-git-dir" "--show-toplevel" "--show-prefix")])
    (cond
      [(not info) (cons #t "undo: this file is not in a git repository")]
      [else
       (let* ([ls (regexp-split #rx"\n" info)]
              [gitdir (car ls)]
              [prefix (if (>= (length ls) 3) (caddr ls) "")])
         (set! ud-file file)
         (set! ud-top (cadr ls))
         (set! ud-rel (string-append prefix name))
         (set! ud-curf (path->string (build-path gitdir (string-append "aiu-undo-cur-" (shadow-key file)))))
         (when (unbox unsaved)
           ((hash-ref commands "save") session (list)))
         (shadow-commit-now! file)
         (ud-load-tree! ud-top ud-rel)
         (when (null? ud-order)
           (shadow-commit-now! file)
           (ud-load-tree! ud-top ud-rel))
         (cond
           [(null? ud-order) (cons #t "undo: no versions yet, save the file first")]
           [else
            (set! ud-orig-text (session-text session))
            (set! ud-orig-point (the-point session))
            (ud-layout!)
            (set! ud-home (or (ud-read-cur) (ud-newest)))
            (set! ud-cur ud-home)
            (set! ud-mark #f)
            (set! ud-diff (list))
            (let ([r (hash-ref ud-resume file #f)])
              (when (and r (hash-ref ud-nodes (car r) #f))
                (set! ud-cur (car r))
                (ud-set-text! session (ud-text (car r)))
                (move-to session (min (cdr r) (ud-blen (ud-text (car r)))))))
            (hash-remove! ud-resume file)
            (set! ud-active #t)
            (set-layer! session "undo")
            (cons #t "undo: h t move, k keep, escape back")]))])))

;; ud-back goes to the parent of the node shown.
(define (ud-back session)
  (let ([p (ud-parent-of ud-cur)])
    (cond [p (hash-set! ud-prefer p ud-cur) (ud-go! session p) (cons #t "undo: back")]
          [else (cons #t "undo: this is the oldest version")])))

;; ud-forward goes to the child that forward follows.
(define (ud-forward session)
  (let ([n (ud-next-of ud-cur)])
    (cond [n (ud-go! session n) (cons #t "undo: forward")]
          [else (cons #t "undo: this is the end of the branch")])))

;; ud-sibling moves to the branch above (step -1) or below (step 1) at a branch point.
(define (ud-sibling session step)
  (let* ([p (ud-parent-of ud-cur)]
         [sibs (if p (hash-ref ud-kids p (list)) ud-roots)]
         [i (ud-index ud-cur sibs)]
         [j (and i (+ i step))])
    (cond [(and j (>= j 0) (< j (length sibs)))
           (when p (hash-set! ud-prefer p (list-ref sibs j)))
           (ud-go! session (list-ref sibs j))
           (cons #t "undo: other branch")]
          [else (cons #t "undo: no branch there")])))

;; ud-branch-back goes back to the last branch point.
(define (ud-branch-back session)
  (let loop ([id (ud-parent-of ud-cur)])
    (cond [(not id) (cons #t "undo: no branch point before this")]
          [(> (length (hash-ref ud-kids id (list))) 1) (ud-go! session id) (cons #t "undo: branch point")]
          [else (loop (ud-parent-of id))])))

;; ud-branch-forward goes forward to the next branch point.
(define (ud-branch-forward session)
  (let loop ([id (ud-next-of ud-cur)])
    (cond [(not id) (cons #t "undo: no branch point ahead")]
          [(> (length (hash-ref ud-kids id (list))) 1) (ud-go! session id) (cons #t "undo: branch point")]
          [else (loop (ud-next-of id))])))

;; ud-tip goes forward to the end of the branch.
(define (ud-tip session)
  (let loop ([id ud-cur])
    (let ([n (ud-next-of id)])
      (cond [n (loop n)]
            [else (ud-go! session id) (cons #t "undo: end of the branch")]))))

;; ud-mark! marks the node shown for the diff.
(define (ud-mark! session) (set! ud-mark ud-cur) (cons #t "undo: marked"))

;; ud-unmark! takes the mark away.
(define (ud-unmark! session) (set! ud-mark #f) (cons #t "undo: unmarked"))

;; ud-show-diff shows the diff between the marked node, or the parent, and the node shown.
(define (ud-show-diff session)
  (let ([base (or ud-mark (ud-parent-of ud-cur))])
    (cond
      [(or (not base) (equal? base ud-cur)) (cons #t "undo: nothing to compare")]
      [else
       (let* ([out (or (ud-git ud-top "diff" "--no-ext-diff" "-U1" base ud-cur "--" ud-rel) "")]
              [lines (filter (lambda (l)
                               (and (> (string-length l) 0)
                                    (not (regexp-match? #rx"^(diff |index |--- |[+][+][+] )" l))))
                             (regexp-split #rx"\n" out))])
         (set! ud-diff (map (lambda (l) (regexp-replace* #rx"\t" l "    ")) lines))
         (cons #t (if (null? lines) "undo: no difference" "undo: diff, any key closes it")))])))

;; ud-restore! puts the live text and point back, as they were when the layer opened.
(define (ud-restore! session)
  (unless (equal? (session-text session) ud-orig-text)
    (ud-set-text! session ud-orig-text))
  (move-to session (min ud-orig-point (ud-blen ud-orig-text)))
  (set-box! unsaved #f))

;; ud-live goes to the live file to paste: the node and the point are remembered, the live text comes
;; back and the write layer opens at the old point.
(define (ud-live session)
  (hash-set! ud-resume ud-file (cons ud-cur (the-point session)))
  (ud-restore! session)
  (set! ud-active #f)
  ((hash-ref commands "write-mode") session (list))
  (cons #t "undo: live file, escape saves, space u comes back to the same node and point"))

;; ud-keep keeps the version shown: it becomes the current node and the file, and the layer closes.
(define (ud-keep session)
  (with-handlers ([void (lambda (e) (void))])
    (call-with-output-file ud-curf
      (lambda (o) (write-string ud-cur o) (newline o))
      #:exists (quote truncate)))
  ((hash-ref commands "save") session (list))
  (set! ud-active #f)
  (hash-remove! ud-resume ud-file)
  ((hash-ref commands "visual-mode") session (list))
  (cons #t "undo: version kept"))

;; ud-cancel rolls back to the live text and closes the layer.
(define (ud-cancel session)
  (ud-restore! session)
  (set! ud-active #f)
  (hash-remove! ud-resume ud-file)
  ((hash-ref commands "visual-mode") session (list))
  (cons #t "undo: rolled back"))

;; ud-reg! adds one command to the undo table. A command other than the first needs the layer open,
;; and the diff view is closed before it runs.
(define (ud-reg! name f open-needed?)
  (hash-set! undo-table name
             (lambda (session words)
               (cond [(and open-needed? (not ud-active)) (cons #t "undo: not open")]
                     [else (set! ud-diff (list)) (f session)]))))

;; The commands of the layer, added when this module is loaded.
(ud-reg! "undo-mode" ud-start! #f)
(ud-reg! "undo-back" ud-back #t)
(ud-reg! "undo-forward" ud-forward #t)
(ud-reg! "undo-up" (lambda (s) (ud-sibling s -1)) #t)
(ud-reg! "undo-down" (lambda (s) (ud-sibling s 1)) #t)
(ud-reg! "undo-branch-back" ud-branch-back #t)
(ud-reg! "undo-branch-forward" ud-branch-forward #t)
(ud-reg! "undo-tip" ud-tip #t)
(ud-reg! "undo-mark" ud-mark! #t)
(ud-reg! "undo-unmark" ud-unmark! #t)
(ud-reg! "undo-diff" ud-show-diff #t)
(ud-reg! "undo-live" ud-live #t)
(ud-reg! "undo-keep" ud-keep #t)
(ud-reg! "undo-cancel" ud-cancel #t)
(set-box! undo-rows-hook ud-rows)
