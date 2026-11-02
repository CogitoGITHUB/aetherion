#lang racket/base
;; One job: the tab commands - change tab, open, close, move and hide the tab bar. They are added to the command table when this module is loaded.

(require racket/list racket/string racket/path "../commands/commands.rkt" "tabs.rkt" "tabs-folders.rkt")

(provide)

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
