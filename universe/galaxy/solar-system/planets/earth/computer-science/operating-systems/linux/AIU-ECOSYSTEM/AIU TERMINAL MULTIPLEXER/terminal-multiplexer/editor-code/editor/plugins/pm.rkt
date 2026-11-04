#lang racket/base

(require racket/file
         racket/list
         racket/string
         "../machine/directories.rkt"
         "../machine/run.rkt")

(define (pm-cli)
  (define named (getenv "AIU_PM_CLI"))
  (if (and named (not (string=? named "")))
      (path->complete-path named)
      (let loop ([at (simplify-path (current-directory))])
        (define up (simplify-path (build-path at "..")))
        (define found (build-path at "AIU-OS" "AIU-PM" "package-manager" "src" "entry" "cli.rkt"))
        (cond
          [(file-exists? found) found]
          [(string=? (path->string at) (path->string up)) #f]
          [else (loop up)]))))

(define (pm-command cli)
  (if (string-suffix? (path->string cli) ".rkt")
      (let ([racket (racket-bin)])
        (if racket
            (list (path->string racket) (path->string cli))
            (list (path->string cli))))
      (list (path->string cli))))

(define (pm-verb args)
  (define cli (pm-cli))
  (cond
    [(not cli)
     (hash 'ok #f 'code -1 'out ""
           'err "the editor does not know where pm is: set AIU_PM_CLI to the pm program")]
    [else
     (define words (append (pm-command cli) (list "--format" "json") args))
     (define result (run-program (string-join (map shell-quote words) " ") 60))
     (hash-set result 'ok (= (hash-ref result 'code -1) 0))]))

(define (pm-apply spec confirmation)
  (if (not confirmation)
      (hash 'ok #f 'code -1 'out ""
            'err "the install was not made: it changes the disk, and the human's confirmation is needed")
      (pm-verb (list "apply" spec "--confirm"))))

(define (pm-verify vault lockfile name)
  (pm-verb (list "verify" vault lockfile name)))

(provide pm-cli
         pm-command
         pm-verb
         pm-apply
         pm-verify)
