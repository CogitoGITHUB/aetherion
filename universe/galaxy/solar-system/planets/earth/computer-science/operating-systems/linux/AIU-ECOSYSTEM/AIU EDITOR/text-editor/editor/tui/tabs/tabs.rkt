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
         "../../commands/commands.rkt"
         "../box.rkt" "tabs-folders.rkt")

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

;; tabs-mark-row answers the text of one row: the names in order with a dot before
;; the active one, cut from the left so the active one stays in view.
(define (tabs-mark-row names active inner)
  (define cells
    (for/list ([n (in-list names)] [i (in-naturals)])
      (if (eqv? i active) (string-append "● " n) n)))
  (define (text s)
    (string-append (if (> s 0) "‹ " "") (string-join (drop cells s) "   ")))
  (let loop ([s 0])
    (if (and active (< s active) (> (string-length (text s)) inner))
        (loop (add1 s))
        (text s))))

;; tabs-scan-maybe lists the workspaces and the projects in a thread, once for each
;; root, and calls again when they are known, so the bar is painted anew.
(define (tabs-scan-maybe root again)
  (define key (path->string root))
  (define have (unbox tab-lists))
  (unless (or (unbox tab-scanning) (and have (string=? (car have) key)))
    (set-box! tab-scanning #t)
    (thread
     (lambda ()
       (define up (tabs-parent root))
       (define ws (if up (tabs-dirs up) null))
       (define ps (tabs-dirs root))
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
  (define labels (tabs-labels files))
  (define at (index-of files (unbox tab-current)))
  (define inner (max 1 (- width 4)))
  (define root (tabs-root file))
  (when (>= level 2) (tabs-scan-maybe root again))
  (define have (unbox tab-lists))
  (define ready (and have (string=? (car have) (path->string root))))
  (define project (tabs-project file root))
  (define tabs-text (tabs-mark-row labels at inner))
  (define project-text
    (if ready (tabs-mark-row (caddr have) (index-of (caddr have) project) inner) "reading folders"))
  (define workspace-text
    (if ready (tabs-mark-row (cadr have) (index-of (cadr have) (tabs-last root)) inner) "reading folders"))
  (define sections
    (append (if (>= level 3) (list (cons "workspace" workspace-text)) null)
            (if (>= level 2) (list (cons "project" project-text)) null)
            (list (cons "tabs" tabs-text)) (list (cons "git" (unbox tab-git-text)))))
  (append (list (edge-line "╭" "╮" (car (car sections)) "" width)
                (body-line (cdr (car sections)) width))
          (append* (for/list ([s (in-list (cdr sections))])
                     (list (edge-line "├" "┤" (car s) "" width) (body-line (cdr s) width))))
          (list (rule-line "╰" "╯" width))))

;; The tabs, for the bar and the live session above them.
(provide tab-files tab-current tab-saved tab-count tab-show!
         tab-switch
         tab-rows
         tab-place
         tab-joined
         tabs-root
         tabs-project-dir)

;; tab-git-text holds the git row as text, set by the git thread of the bar, so
;; the tab bar shows it at every level.
(define tab-git-text (box "reading git"))

(provide tab-git-text)
