#lang racket/base
(require racket/file racket/string)
(define (fail message) (eprintf "FAILED: ~a\n" message) (exit 1))
(define (count-of old text) (length (regexp-match* (regexp (regexp-quote old)) text)))
(define (replace-once text old new done-marker label)
  (define n (count-of old text))
  (cond [(= n 1) (string-replace text old new)]
        [(and (= n 0) (string-contains? text done-marker)) text]
        [else (fail (string-append "anchor failed: " label))]))
(define src "AIU-OS/AIU-PM/package-manager/src")
(define spec-path (string-append src "/spec/spec.rkt"))
(define source-path (string-append src "/spec/spec-source.rkt"))
(define todo-path "todo.aiu")
(define starting-path "ai-starting-point.md")
(for ([p (list spec-path source-path todo-path starting-path)])
  (unless (file-exists? p) (fail (string-append "missing " p))))
(define struct-new #<<X
(struct local-source (path)
  #:transparent
  #:guard (lambda (path _name)
            (unless (and (string? path) (> (string-length path) 0))
              (raise-pm-error (quote spec) (quote local-source) "path must be a nonempty string"
                              #:fields (list (cons "value" (format "~s" path)))))
            path))
;; path : string?  a folder on this machine that is the source, no upstream

(struct dep (name version)
X
  )
(define reader-new #<<X
(define (read-source form)
  (if (local-source-form? form)
      (read-local-source form)
      (read-git-source form)))

(define (local-source-form? form)
  (define inner (syntax->list (car (field-args form 1 (quote source)))))
  (and inner
       (= (length inner) 2)
       (eq? (syntax->datum (car inner)) (quote local))))

(define (read-local-source form)
  (define inner (syntax->list (car (field-args form 1 (quote source)))))
  (define path (syntax->datum (cadr inner)))
  (unless (and (string? path) (> (string-length path) 0))
    (fail (cadr inner) "local source must be a nonempty path string"))
  (local-source path))

(define (read-git-source form)
X
  )
(define spec-in (file->string spec-path))
(define spec-1 (replace-once spec-in " (struct-out source)\n (struct-out dep)" " (struct-out source)\n (struct-out local-source)\n (struct-out dep)" "(struct-out local-source)" "spec provide"))
(define spec-2 (replace-once spec-1 "(struct dep (name version)" struct-new "(struct local-source (path)" "spec struct dep"))
(define spec-3 (replace-once spec-2 "(unless (source? source)" "(unless (or (source? source) (local-source? source))" "(local-source? source)" "spec guard source?"))
(define source-in (file->string source-path))
(define source-1 (replace-once source-in "(define (read-source form)" reader-new "(define (read-git-source form)" "read-source header"))
(define todo-in (file->string todo-path))
(define item-old "todo: package manager local first: new source form (local PATH) next to (git URL COMMIT); a local package installs from its live folder like dev mode, no clone, no commit pin; a tree fingerprint replaces the commit; read apply.rkt, plan-derive.rkt, plan-actions.rkt, lockfile.rkt and dev-link.rkt first\nPlanned.\nparagraph end\n\n")
(define (paragraph text) (string-append "paragraph start\ntodo: " text "\nPlanned.\nparagraph end\n\n"))
(define item-new
  (string-append
   "todo: package manager local first, stage 2: a pin for a local source, the tree fingerprint from store/content-address.rkt tree-hash; spec, plan-derive and the lockfile use that pin where they use source-commit now\nPlanned.\nparagraph end\n\n"
   (paragraph "package manager local first, stage 3: apply installs a local package by copying its folder into staging instead of fetch and export from the vault; skip the vault preflight for local sources; manifest entry for a local package")
   (paragraph "package manager local first, stage 4: the lockfile accepts a local source without the git URL check; the ecosystem manifest declares every package as (local PATH)")))
(define todo-1 (replace-once todo-in item-old item-new "local first, stage 2" "todo item local first"))
(define starting-text (file->string starting-path))
(define starting-line
  "- PM local first stage 1 2026-11-07: spec.rkt has a local-source struct (path) accepted as a spec source, spec-source.rkt reads (local PATH); todo split into stages 2 to 4; apply and the lockfile still need the pin; NEXT STEP: read the apply performer, content-address tree-hash and plan-hash, then patch stage 2\n")
(display-to-file spec-3 spec-path #:exists (quote truncate))
(display-to-file source-1 source-path #:exists (quote truncate))
(display-to-file todo-1 todo-path #:exists (quote truncate))
(unless (string-contains? starting-text "PM local first stage 1 2026-11-07")
  (display-to-file (string-append starting-line starting-text) starting-path #:exists (quote truncate)))
(printf "ok\n")
