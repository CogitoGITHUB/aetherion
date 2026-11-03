#lang racket/base

(require racket/list
         racket/string
         racket/path
         "../../commands/commands.rkt"
         "../float/box.rkt" "tabs-folders.rkt")

(define tab-files (box (list)))

(define tab-current (box #f))

(define tab-switch (box #f))

(define tab-place (box "bottom"))

(define tab-saved (box "bottom"))

(define tab-count (box 3))

(define tab-joined (box #t))

(define project-order (box #f))
(define project-hidden (box (list)))
(define workspace-order (box #f))
(define workspace-hidden (box (list)))

(define (tabs-arranged names order hidden current)
  (define shown (filter (lambda (n) (or (equal? n current) (not (member n (unbox hidden))))) names))
  (define o (or (unbox order) (list)))
  (define known (filter (lambda (n) (member n shown)) o))
  (append known (filter (lambda (n) (not (member n known))) shown)))

(define tab-lists (box #f))

(define tab-scanning (box #f))

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

(define (tabs-order-moved files current delta)
  (define at (index-of files current))
  (define to (and at (+ at delta)))
  (if (or (not at) (< to 0) (>= to (length files)))
      files
      (let ([v (list->vector files)])
        (vector-set! v at (vector-ref v to))
        (vector-set! v to (list-ref files at))
        (vector->list v))))

(define (tab-show! file)
  (unless (member file (unbox tab-files))
    (set-box! tab-files (append (unbox tab-files) (list file))))
  (set-box! tab-current file))

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
    (if ready (let ([l (tabs-arranged (caddr have) project-order project-hidden project)]) (tabs-mark-row l (index-of l project) inner)) "reading folders"))
  (define workspace-text
    (if ready (let ([l (tabs-arranged (cadr have) workspace-order workspace-hidden (tabs-last root))]) (tabs-mark-row l (index-of l (tabs-last root)) inner)) "reading folders"))
  (define sections
    (append (if (>= level 3) (list (cons "workspace" workspace-text)) null)
            (if (>= level 2) (list (cons "project" project-text)) null)
            (list (cons "tabs" tabs-text)) (list (cons "git" (unbox tab-git-text)))))
  (append (list (edge-line "╭" "╮" (car (car sections)) "" width)
                (body-line (cdr (car sections)) width))
          (append* (for/list ([s (in-list (cdr sections))])
                     (list (edge-line "├" "┤" (car s) "" width) (body-line (cdr s) width))))
          (list (rule-line "╰" "╯" width))))

(provide tabs-order-moved tab-files tab-current tab-saved tab-count tab-show!
         tab-switch
         tab-rows
         tab-place
         tab-joined
         tabs-root
         tabs-project-dir)

(define tab-git-text (box "reading git"))

(provide tab-git-text)
(provide project-order project-hidden workspace-order workspace-hidden tabs-arranged)
(provide tab-lists)
