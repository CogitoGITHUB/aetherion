#lang racket/base

(require racket/list racket/string racket/path "../../commands/commands-shared.rkt" "tabs-shared.rkt" "tabs-folders-shared.rkt" (only-in "../bar/bar-state-shared.rkt" name-prompt))

(provide)

(define (tabs-go! target)
  (set-box! tab-current target)
  (set-box! tab-switch target)
  (cons #f ""))

(define (tabs-step delta)
  (define files (unbox tab-files))
  (define i (index-of files (unbox tab-current)))
  (if (or (not i) (< (length files) 2))
      (cons #t "one tab")
      (tabs-go! (list-ref files (modulo (+ i delta) (length files))))))

(define (command-tab-prev session words) (tabs-step -1))

(define (command-tab-next session words) (tabs-step 1))

(define (command-tab-open session words)
  (define file (path->string (path->complete-path (session-file session))))
  (define dir (tabs-parent file))
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
     (tabs-go! (car fresh))]))

(define (command-tab-close session words)
  (define files (unbox tab-files))
  (define cur (unbox tab-current))
  (cond
    [(< (length files) 2) (cons #t "the last tab stays")]
    [else
     (define i (or (index-of files cur) 0))
     (define rest (remove cur files))
     (set-box! tab-files rest)
     (tabs-go! (list-ref rest (min i (sub1 (length rest)))))]))

(define (tabs-put-place! p)
  (set-box! tab-place p)
  (set-box! tab-saved p))

(define (command-tab-place-next session words)
  (define now (if (string=? (unbox tab-place) "hidden") (unbox tab-saved) (unbox tab-place)))
  (tabs-put-place! (if (string=? now "top") "bottom" "top"))
  (cons #t (format "tabs: ~a" (unbox tab-place))))

(define (command-tab-top session words) (tabs-put-place! "top") (cons #t "tabs: top"))

(define (command-tab-bottom session words) (tabs-put-place! "bottom") (cons #t "tabs: bottom"))

(define (command-tab-join session words)
  (set-box! tab-joined (not (unbox tab-joined)))
  (cons #t (if (unbox tab-joined) "tabs: joined" "tabs: apart")))

(define (command-tab-hide session words)
  (cond [(string=? (unbox tab-place) "hidden") (set-box! tab-place (unbox tab-saved))]
        [else (set-box! tab-saved (unbox tab-place))
              (set-box! tab-place "hidden")])
  (cons #t (format "tabs: ~a" (unbox tab-place))))

(define (command-tab-less session words)
  (set-box! tab-count (max 1 (sub1 (unbox tab-count))))
  (cons #t (format "tab level: ~a" (unbox tab-count))))

(define (command-tab-more session words)
  (set-box! tab-count (min 3 (add1 (unbox tab-count))))
  (cons #t (format "tab level: ~a" (unbox tab-count))))

(define (command-tab-mode session words)
  (set-layer! session "tab")
  (cons #t "layer: tab"))

(define (command-tab-level-mode session words)
  (set-layer! session "tab-level")
  (cons #t "layer: tab-level"))

(define (tabs-move! delta)
  (define files (unbox tab-files))
  (define moved (tabs-order-moved files (unbox tab-current) delta))
  (cond
    [(equal? moved files) (cons #t "the tab cannot move further")]
    [else (set-box! tab-files moved) (cons #t (if (< delta 0) "tab moved left" "tab moved right"))]))

(define (command-tab-move-left session words) (tabs-move! -1))

(define (command-tab-move-right session words) (tabs-move! 1))

(hash-set! commands "tab-move-left" command-tab-move-left)
(hash-set! commands "tab-move-right" command-tab-move-right)
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

(define (page-in dir depth)
  (with-handlers ([(lambda (e) #t) (lambda (e) #f)])
    (let ([es (sort (map path->string (directory-list dir)) string<?)])
      (or (for/first ([n (in-list es)]
                      #:when (and (regexp-match? #rx"[.]aiu$" n) (file-exists? (build-path dir n))))
            (path->string (build-path dir n)))
          (and (> depth 0)
               (for/or ([n (in-list es)]
                        #:when (and (directory-exists? (build-path dir n))
                                    (not (char=? (string-ref n 0) #\.))
                                    (not (member n tabs-skipped))))
                 (page-in (build-path dir n) (sub1 depth))))))))

(define (hop-step! names current dir-of delta label)
  (define i (index-of names current))
  (cond
    [(or (not i) (< (length names) 2)) (cons #t (string-append "one " label))]
    [else
     (let loop ([k 1])
       (cond
         [(>= k (length names)) (cons #t (string-append "no page in any other " label))]
         [else
          (let* ([n (list-ref names (modulo (+ i (* k delta)) (length names)))]
                 [page (page-in (dir-of n) 2)])
            (cond
              [page (tab-show! page) (tabs-go! page)]
              [else (loop (add1 k))]))]))]))

(define (project-hop session delta)
  (define file (path->string (path->complete-path (session-file session))))
  (define root (tabs-root file))
  (hop-step! (tabs-arranged (tabs-dirs root) project-order project-hidden (tabs-project file root)) (tabs-project file root) (lambda (n) (build-path root n)) delta "project"))

(define (workspace-hop session delta)
  (define file (path->string (path->complete-path (session-file session))))
  (define root (tabs-root file))
  (define up (tabs-parent root))
  (if up
      (hop-step! (tabs-arranged (tabs-dirs up) workspace-order workspace-hidden (tabs-last root)) (tabs-last root) (lambda (n) (build-path up n)) delta "workspace")
      (cons #t "no workspace folder")))

(define (command-project-prev session words) (project-hop session -1))
(define (command-project-next session words) (project-hop session 1))
(define (command-workspace-prev session words) (workspace-hop session -1))
(define (command-workspace-next session words) (workspace-hop session 1))
(define (command-project-mode session words) (set-layer! session "project") (cons #t "layer: project"))
(define (command-workspace-mode session words) (set-layer! session "workspace") (cons #t "layer: workspace"))

(for ([p (list (cons "project-prev" command-project-prev) (cons "project-next" command-project-next) (cons "workspace-prev" command-workspace-prev) (cons "workspace-next" command-workspace-next) (cons "project-mode" command-project-mode) (cons "workspace-mode" command-workspace-mode))])
  (hash-set! commands (car p) (cdr p)))

(define (arrange-move! kind names order current delta)
  (define moved (tabs-order-moved names current delta))
  (cond
    [(equal? moved names) (cons #t (string-append "the " kind " cannot move further"))]
    [else (set-box! order moved) (cons #t (string-append kind (if (< delta 0) " moved left" " moved right")))]))

(define (project-names session)
  (define file (path->string (path->complete-path (session-file session))))
  (define root (tabs-root file))
  (values file root (tabs-project file root)))

(define (command-project-move-left session words)
  (define-values (file root cur) (project-names session))
  (arrange-move! "project" (tabs-arranged (tabs-dirs root) project-order project-hidden cur) project-order cur -1))
(define (command-project-move-right session words)
  (define-values (file root cur) (project-names session))
  (arrange-move! "project" (tabs-arranged (tabs-dirs root) project-order project-hidden cur) project-order cur 1))
(define (command-workspace-move-left session words)
  (define-values (file root cur) (project-names session))
  (define up (tabs-parent root))
  (if up (arrange-move! "workspace" (tabs-arranged (tabs-dirs up) workspace-order workspace-hidden (tabs-last root)) workspace-order (tabs-last root) -1) (cons #t "no workspace folder")))
(define (command-workspace-move-right session words)
  (define-values (file root cur) (project-names session))
  (define up (tabs-parent root))
  (if up (arrange-move! "workspace" (tabs-arranged (tabs-dirs up) workspace-order workspace-hidden (tabs-last root)) workspace-order (tabs-last root) 1) (cons #t "no workspace folder")))

(define (command-project-close session words)
  (define-values (file root cur) (project-names session))
  (cond
    [(< (length (tabs-arranged (tabs-dirs root) project-order project-hidden cur)) 2) (cons #t "the last project stays")]
    [else (set-box! project-hidden (cons cur (unbox project-hidden))) (project-hop session 1)]))
(define (command-workspace-close session words)
  (define-values (file root cur) (project-names session))
  (define up (tabs-parent root))
  (cond
    [(not up) (cons #t "no workspace folder")]
    [(< (length (tabs-arranged (tabs-dirs up) workspace-order workspace-hidden (tabs-last root))) 2) (cons #t "the last workspace stays")]
    [else (set-box! workspace-hidden (cons (tabs-last root) (unbox workspace-hidden))) (workspace-hop session 1)]))
(define (command-project-open session words) (set-box! project-hidden (list)) (cons #t "all projects shown"))
(define (command-workspace-open session words) (set-box! workspace-hidden (list)) (cons #t "all workspaces shown"))

(for ([p (list (cons "project-move-left" command-project-move-left) (cons "project-move-right" command-project-move-right) (cons "workspace-move-left" command-workspace-move-left) (cons "workspace-move-right" command-workspace-move-right) (cons "project-close" command-project-close) (cons "workspace-close" command-workspace-close) (cons "project-open" command-project-open) (cons "workspace-open" command-workspace-open))])
  (hash-set! commands (car p) (cdr p)))

(define (ask-name! label cb)
  (set-box! name-prompt (list label "" cb ""))
  (cons #t "type the name"))

(define (make-new! parent name label)
  (define dir (build-path parent name))
  (cond
    [(or (directory-exists? dir) (file-exists? dir)) (cons #t (string-append "that " label " already exists"))]
    [else
     (with-handlers ([(lambda (e) #t) (lambda (e) (cons #t (string-append "could not create " label)))])
       (make-directory dir)
       (define page (build-path dir "page.aiu"))
       (call-with-output-file page (lambda (o) (fprintf o "title start\nkind: default\ntags: page\n~a\ntitle end\n" (string-upcase name))))
       (set-box! tab-lists #f)
       (tab-show! (path->string page))
       (tabs-go! (path->string page)))]))

(define (remove-dir! dir hop label)
  (define target (build-path (or (tabs-parent dir) (current-directory)) (string-append ".removed-" (tabs-last dir))))
  (cond
    [(or (directory-exists? target) (file-exists? target)) (cons #t (string-append label " already removed once: " (path->string target)))]
    [else
     (define r (hop))
     (cond
       [(car r) r]
       [else
        (with-handlers ([(lambda (e) #t) (lambda (e) (cons #t (string-append "could not remove " label)))])
          (define prefix (string-append (path->string dir) "/"))
          (rename-file-or-directory dir target)
          (set-box! tab-files (filter (lambda (f) (not (string-prefix? f prefix))) (unbox tab-files)))
          (set-box! tab-lists #f)
          r)])]))

(define (command-project-new session words)
  (define-values (file root cur) (project-names session))
  (ask-name! "project" (lambda (nm) (make-new! root nm "project"))))
(define (command-workspace-new session words)
  (define-values (file root cur) (project-names session))
  (define up (tabs-parent root))
  (if up (ask-name! "workspace" (lambda (nm) (make-new! up nm "workspace"))) (cons #t "no workspace folder")))
(define (command-project-remove session words)
  (define-values (file root cur) (project-names session))
  (remove-dir! (build-path root cur) (lambda () (project-hop session 1)) "project"))
(define (command-workspace-remove session words)
  (define-values (file root cur) (project-names session))
  (remove-dir! root (lambda () (workspace-hop session 1)) "workspace"))

(for ([p (list (cons "project-new" command-project-new) (cons "workspace-new" command-workspace-new) (cons "project-remove" command-project-remove) (cons "workspace-remove" command-workspace-remove))])
  (hash-set! commands (car p) (cdr p)))

(define (next-number dir)
  (let loop ([n (add1 (length (tabs-dirs dir)))])
    (if (directory-exists? (build-path dir (number->string n))) (loop (add1 n)) (number->string n))))

(define (pick-name nm dir) (if (string=? nm "") (next-number dir) nm))

(define (rename-dir! dir new label)
  (cond
    [(or (directory-exists? new) (file-exists? new)) (cons #t (string-append "that " label " already exists"))]
    [else
     (with-handlers ([(lambda (e) #t) (lambda (e) (cons #t (string-append "could not rename " label)))])
       (define old (string-append (path->string dir) "/"))
       (define fresh (string-append (path->string new) "/"))
       (define (moved f) (if (and (string? f) (string-prefix? f old)) (string-append fresh (substring f (string-length old))) f))
       (define cur (unbox tab-current))
       (rename-file-or-directory dir new)
       (set-box! tab-files (map moved (unbox tab-files)))
       (set-box! tab-lists #f)
       (tabs-go! (moved cur)))]))

(define (command-project-new-auto session words)
  (define-values (file root cur) (project-names session))
  (ask-name! "project" (lambda (nm) (make-new! root (pick-name nm root) "project"))))

(define (command-workspace-new-auto session words)
  (define-values (file root cur) (project-names session))
  (define up (tabs-parent root))
  (if up
      (ask-name! "workspace" (lambda (nm) (make-new! up (pick-name nm up) "workspace")))
      (cons #t "no workspace folder")))

(define (command-project-rename session words)
  (define-values (file root cur) (project-names session))
  (ask-name! "rename project" (lambda (nm) (rename-dir! (build-path root cur) (build-path root nm) "project"))))

(define (command-workspace-rename session words)
  (define-values (file root cur) (project-names session))
  (define up (tabs-parent root))
  (if up
      (ask-name! "rename workspace" (lambda (nm) (rename-dir! root (build-path up nm) "workspace")))
      (cons #t "no workspace folder")))

(hash-set! commands "project-new" command-project-new-auto)
(hash-set! commands "workspace-new" command-workspace-new-auto)
(hash-set! commands "project-rename" command-project-rename)
(hash-set! commands "workspace-rename" command-workspace-rename)
(define (rename-tab! base cur nm)
  (define new (path->string (build-path base nm)))
  (cond
    [(or (string=? nm ".aiu") (file-exists? new) (directory-exists? new)) (cons #t "that tab already exists")]
    [else
     (with-handlers ([(lambda (e) #t) (lambda (e) (cons #t "could not rename tab"))])
       (rename-file-or-directory cur new)
       (set-box! tab-files (map (lambda (f) (if (equal? f cur) new f)) (unbox tab-files)))
       (set-box! tab-lists #f)
       (tabs-go! new))]))
(define (command-tab-rename session words)
  (define cur (unbox tab-current))
  (define-values (base name dir?) (split-path cur))
  (ask-name! "rename tab" (lambda (nm) (rename-tab! base cur (if (regexp-match? #rx"[.]aiu$" nm) nm (string-append nm ".aiu"))))))
(hash-set! commands "tab-rename" command-tab-rename)
(for ([p (list (cons "tab-move-mode" "tab-move") (cons "project-move-mode" "project-move") (cons "workspace-move-mode" "workspace-move") (cons "tab-move-back" "tab") (cons "project-move-back" "project") (cons "workspace-move-back" "workspace"))])
  (hash-set! commands (car p) (let ([layer (cdr p)]) (lambda (session words) (set-layer! session layer) (cons #t (string-append "layer: " layer))))))

