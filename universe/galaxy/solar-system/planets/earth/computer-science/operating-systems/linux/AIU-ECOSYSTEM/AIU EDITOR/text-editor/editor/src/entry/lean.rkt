#lang racket/base
;; One job: the lean edit, the live session without the agent side. It loads
;; only what a person needs to read and write a page: the commands, the keys,
;; the screen and the home screen. The send, the audit and the checkpoint code
;; load when the send key is first pressed. Scripted runs and every other verb
;; use cli-full.rkt, which loads everything.

(require racket/path racket/port
         "../machine/directories.rkt"
         "../commands/commands.rkt"
         "../dashboard/explorer.rkt"
         "../dashboard/home.rkt"
         "live.rkt")

;; here is the folder of this file, so the send module can be found by name.
(define here
  (let-values ([(base name dir?)
                (split-path (variable-reference->module-source (#%variable-reference)))])
    base))

;; stub-send is the send key until the send code is loaded: it loads the code,
;; which puts the real command in the table, and runs that.
(define (stub-send session words)
  (dynamic-require (simplify-path (build-path here (quote up) "send" "send.rkt")) #f)
  (define real (hash-ref commands "send" #f))
  (if (and real (not (eq? real stub-send)))
      (real session words)
      (cons #t "the send could not be loaded")))

(hash-set! commands "send" stub-send)

;; file-session opens the file in the live session.
(define (file-session path)
  (define file (path->complete-path path))
  (define journal (journal-path-for file))
  (ensure-dir (build-path (state-dir) "journal"))
  (live-session file journal)
  (when (unbox home-request)
    (set-box! home-request #f)
    (home-session)))

;; home-session runs the home screen. A page picked there opens in the live
;; session when the home screen ends.
(define (home-session)
  (define file (path->complete-path "dashboard"))
  (define journal (journal-path-for file))
  (ensure-dir (build-path (state-dir) "journal"))
  (set-box! home-chosen #f)
  (parameterize ([home-screen home-lines]
                 [home-pick home-page]
                 [home-refresh home-rescan!])
    (live-session file journal))
  (define chosen (unbox home-chosen))
  (when chosen
    (set-box! home-chosen #f)
    (file-session chosen)))

;; lean-edit runs the edit verb: the home screen with no file, else the file.
(define (lean-edit args)
  (if (null? args)
      (home-session)
      (file-session (car args))))

;; The lean edit, for the entry above it.
(provide lean-edit)
