#lang racket/base
;; One job: the tabs. It keeps the files open in the editor, the active tab, the
;; place and the level of the tab bar, and it builds the rows of the bar: the
;; tabs, the project and the workspace, each in its own section of one box. It
;; holds the commands that change tab, open the next page of the folder, close a
;; tab and change the bar. The live screen asks for the rows at each paint; the
;; folders are listed in a thread, never in a paint.

(require racket/list
         racket/string
         racket/path
         "../commands/commands.rkt"
         "box.rkt")

;; tab-files holds the open files, as complete paths in text, in the order opened.
(define tab-files (box (list)))

;; tab-current holds the active file.
(define tab-current (box #f))

;; tab-switch holds the file the live session must open next, or nothing.
(define tab-switch (box #f))

;; tab-place holds where the tab bar stands: top, bottom or hidden.
(define tab-place (box "top"))

;; tab-saved holds the place the tab bar had before it was hidden.
(define tab-saved (box "top"))

;; tab-count holds the level: 1 tabs, 2 project and tabs, 3 workspace, project and tabs.
;; It starts at 3, every level shown, and the person lowers it when needed.
(define tab-count (box 3))

;; tab-joined holds whether the tab bar shares its edge with the bar when both
;; stand at the same edge of the screen.
(define tab-joined (box #t))

;; tab-lists holds the folders found: the root they belong to, the workspaces and
;; the projects.
(define tab-lists (box #f))

;; tab-scanning holds whether a thread is listing the folders now.
(define tab-scanning (box #f))

;; tb-skipped are the folder names the listing never shows.
(define tb-skipped (list "compiled" "node_modules" "target" "aiu-compiled"))

;; tb-last answers the last name of a path, or nothing when there is none.
(define (tb-last p)
  (cond
    [(not (or (string? p) (path? p))) ""]
    [else
     (define-values (base name dir?) (split-path (if (string? p) (string->path p) p)))
     (if (path? name) (path->string name) "")]))

;; tb-parent answers the folder of a path, or false at the top.
(define (tb-parent p)
  (define-values (base name dir?) (split-path (if (string? p) (string->path p) p)))
  (and (path? base) base))

;; tb-labels answers the name of each tab; two tabs with one name show their folder too.
(define (tb-labels files)
  (define names (map tb-last files))
  (for/list ([f (in-list files)] [n (in-list names)])
    (if (> (length (filter (lambda (x) (string=? x n)) names)) 1)
        (string-append (tb-last (tb-parent f)) "/" n)
        n)))

;; tb-root answers the workspace folder of a file: AIU_ROOT when it is set, else
;; the folder named AIU-ECOSYSTEM above the file, else the folder of the file.
(define (tb-root file)
  (define given (getenv "AIU_ROOT"))
  (cond
    [(and given (directory-exists? given)) (string->path given)]
    [else
     (let loop ([dir (tb-parent file)])
       (cond
         [(not dir) (or (tb-parent file) (current-directory))]
         [(string=? (tb-last dir) "AIU-ECOSYSTEM") dir]
         [else (loop (tb-parent dir))]))]))

;; tb-project answers the project of a file: the first folder under the root, or
;; the folder of the file when it is not under a folder of the root.
(define (tb-project file root)
  (define rel (find-relative-path root (string->path file)))
  (define parts (if (relative-path? rel) (explode-path rel) null))
  (if (and (> (length parts) 1) (path? (car parts)))
      (path->string (car parts))
      (tb-last (tb-parent file))))

;; tb-project-dir answers the folder of the project of a file: the folder named by
;; the project under the root, or the folder of the file when there is none.
(define (tb-project-dir file root)
  (define candidate (build-path root (tb-project file root)))
  (if (directory-exists? candidate)
      candidate
      (or (tb-parent file) (current-directory))))

;; tb-dirs answers the names of the folders in a folder, in order, without the
;; hidden ones and the skipped ones.
(define (tb-dirs dir)
  (with-handlers ([(lambda (e) #t) (lambda (e) null)])
    (sort (for/list ([e (in-list (directory-list dir))]
                     #:when (let ([n (path->string e)])
                              (and (directory-exists? (build-path dir e))
                                   (not (char=? (string-ref n 0) #\.))
                                   (not (member n tb-skipped)))))
            (path->string e))
          string<?)))

;; tb-mark-row answers the text of one row: the names in order with a dot before
;; the active one, cut from the left so the active one stays in view.
(define (tb-mark-row names active inner)
  (define cells
    (for/list ([n (in-list names)] [i (in-naturals)])
      (if (eqv? i active) (string-append "● " n) n)))
  (define (text s)
    (string-append (if (> s 0) "‹ " "") (string-join (drop cells s) "   ")))
  (let loop ([s 0])
    (if (and active (< s active) (> (string-length (text s)) inner))
        (loop (add1 s))
        (text s))))

;; tb-scan-maybe lists the workspaces and the projects in a thread, once for each
;; root, and calls again when they are known, so the bar is painted anew.
(define (tb-scan-maybe root again)
  (define key (path->string root))
  (define have (unbox tab-lists))
  (unless (or (unbox tab-scanning) (and have (string=? (car have) key)))
    (set-box! tab-scanning #t)
    (thread
     (lambda ()
       (define up (tb-parent root))
       (define ws (if up (tb-dirs up) null))
       (define ps (tb-dirs root))
       (set-box! tab-lists (list key ws ps))
       (set-box! tab-scanning #f)
       (again)))))

;; tab-show! adds a file to the tabs when it is not there and makes it active.
(define (tab-show! file)
  (unless (member file (unbox tab-files))
    (set-box! tab-files (append (unbox tab-files) (list file))))
  (set-box! tab-current file))

;; tab-rows answers the rows of the tab bar for a file and a width: one box with a
;; section for each level shown, the active workspace, project and tab marked.
(define (tab-rows file width again)
  (define level (min 3 (max 1 (unbox tab-count))))
  (define files (unbox tab-files))
  (define labels (tb-labels files))
  (define at (index-of files (unbox tab-current)))
  (define inner (max 1 (- width 4)))
  (define root (tb-root file))
  (when (>= level 2) (tb-scan-maybe root again))
  (define have (unbox tab-lists))
  (define ready (and have (string=? (car have) (path->string root))))
  (define project (tb-project file root))
  (define tabs-text (tb-mark-row labels at inner))
  (define project-text
    (if ready (tb-mark-row (caddr have) (index-of (caddr have) project) inner) "reading folders"))
  (define workspace-text
    (if ready (tb-mark-row (cadr have) (index-of (cadr have) (tb-last root)) inner) "reading folders"))
  (define sections
    (append (if (>= level 3) (list (cons "workspace" workspace-text)) null)
            (if (>= level 2) (list (cons "project" project-text)) null)
            (list (cons "tabs" tabs-text))))
  (append (list (edge-line "╭" "╮" (car (car sections)) "" width)
                (body-line (cdr (car sections)) width))
          (append* (for/list ([s (in-list (cdr sections))])
                     (list (edge-line "├" "┤" (car s) "" width) (body-line (cdr s) width))))
          (list (rule-line "╰" "╯" width))))

;; tb-go! makes a file the active tab and ends the round of the live session, so
;; the session opens that file next.
(define (tb-go! target)
  (set-box! tab-current target)
  (set-box! tab-switch target)
  (cons #f ""))

;; tb-step goes to the tab before (-1) or after (1) the active one, and round.
(define (tb-step delta)
  (define files (unbox tab-files))
  (define i (index-of files (unbox tab-current)))
  (if (or (not i) (< (length files) 2))
      (cons #t "one tab")
      (tb-go! (list-ref files (modulo (+ i delta) (length files))))))

;; command-tab-prev goes to the tab before.
(define (command-tab-prev session words) (tb-step -1))

;; command-tab-next goes to the tab after.
(define (command-tab-next session words) (tb-step 1))

;; command-tab-open opens the next page of the folder of the active file that is
;; not open yet, as a new tab.
(define (command-tab-open session words)
  (define file (path->string (path->complete-path (session-file session))))
  (define dir (tb-parent file))
  (define names
    (if dir
        (with-handlers ([(lambda (e) #t) (lambda (e) null)])
          (sort (for/list ([e (in-list (directory-list dir))]
                           #:when (regexp-match? #rx"[.]aiu$" (path->string e)))
                  (path->string (build-path dir e)))
                string<?))
        null))
  (define fresh (filter (lambda (p) (not (member p (unbox tab-files)))) names))
  (cond
    [(null? fresh) (cons #t "no other page in this folder")]
    [else
     (set-box! tab-files (append (unbox tab-files) (list (car fresh))))
     (tb-go! (car fresh))]))

;; command-tab-close closes the active tab and goes to the one beside it. The
;; last tab stays.
(define (command-tab-close session words)
  (define files (unbox tab-files))
  (define cur (unbox tab-current))
  (cond
    [(< (length files) 2) (cons #t "the last tab stays")]
    [else
     (define i (or (index-of files cur) 0))
     (define rest (remove cur files))
     (set-box! tab-files rest)
     (tb-go! (list-ref rest (min i (sub1 (length rest)))))]))

;; tb-put-place! stands the tab bar at a place and keeps the place for the hide key.
(define (tb-put-place! p)
  (set-box! tab-place p)
  (set-box! tab-saved p))

;; command-tab-place-next moves the tab bar between the top and the bottom. A
;; hidden bar comes back first.
(define (command-tab-place-next session words)
  (define now (if (string=? (unbox tab-place) "hidden") (unbox tab-saved) (unbox tab-place)))
  (tb-put-place! (if (string=? now "top") "bottom" "top"))
  (cons #t (format "tabs: ~a" (unbox tab-place))))

;; command-tab-top stands the tab bar at the top.
(define (command-tab-top session words) (tb-put-place! "top") (cons #t "tabs: top"))

;; command-tab-bottom stands the tab bar at the bottom.
(define (command-tab-bottom session words) (tb-put-place! "bottom") (cons #t "tabs: bottom"))

;; command-tab-join switches between a shared edge and two boxes when the tab bar
;; and the bar stand at the same edge.
(define (command-tab-join session words)
  (set-box! tab-joined (not (unbox tab-joined)))
  (cons #t (if (unbox tab-joined) "tabs: joined" "tabs: apart")))

;; command-tab-hide hides the tab bar, or shows it again where it stood.
(define (command-tab-hide session words)
  (cond [(string=? (unbox tab-place) "hidden") (set-box! tab-place (unbox tab-saved))]
        [else (set-box! tab-saved (unbox tab-place))
              (set-box! tab-place "hidden")])
  (cons #t (format "tabs: ~a" (unbox tab-place))))

;; command-tab-less hides one level of the tab bar; the tabs always stay.
(define (command-tab-less session words)
  (set-box! tab-count (max 1 (sub1 (unbox tab-count))))
  (cons #t (format "tab level: ~a" (unbox tab-count))))

;; command-tab-more shows one more level of the tab bar.
(define (command-tab-more session words)
  (set-box! tab-count (min 3 (add1 (unbox tab-count))))
  (cons #t (format "tab level: ~a" (unbox tab-count))))

;; command-tab-mode enters the tab layer.
(define (command-tab-mode session words)
  (set-layer! session "tab")
  (cons #t "layer: tab"))

;; command-tab-level-mode enters the level adjuster of the tab bar.
(define (command-tab-level-mode session words)
  (set-layer! session "tab-level")
  (cons #t "layer: tab-level"))

;; The commands are added to the command table when this module is loaded, so the
;; keys find them and the gate sees the same table the editor does.
(hash-set! commands "tab-mode" command-tab-mode)
(hash-set! commands "tab-level-mode" command-tab-level-mode)
(hash-set! commands "tab-prev" command-tab-prev)
(hash-set! commands "tab-next" command-tab-next)
(hash-set! commands "tab-open" command-tab-open)
(hash-set! commands "tab-close" command-tab-close)
(hash-set! commands "tab-place-next" command-tab-place-next)
(hash-set! commands "tab-top" command-tab-top)
(hash-set! commands "tab-bottom" command-tab-bottom)
(hash-set! commands "tab-join" command-tab-join)
(hash-set! commands "tab-hide" command-tab-hide)
(hash-set! commands "tab-less" command-tab-less)
(hash-set! commands "tab-more" command-tab-more)

;; The tabs, for the bar and the live session above them.
(provide tab-show!
         tab-switch
         tab-rows
         tab-place
         tab-joined
         tb-root
         tb-project-dir)
