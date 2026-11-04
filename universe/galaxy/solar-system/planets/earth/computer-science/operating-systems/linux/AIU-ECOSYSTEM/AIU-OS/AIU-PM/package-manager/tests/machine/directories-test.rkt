#lang racket/base
;; directories-test.rkt -- the moved-out test submodule of src/machine/directories.rkt.
;; Step 14 of TODO.org phase A: inline tests live under
;; package-manager/tests/, mirroring package-manager/src/ one
;; area to one area. The require list below is the module's OWN
;; list, redirected at src/ where it used to point at a sibling
;; area, plus the module itself: this body could already see
;; everything it uses, so nothing new can reach in.

(require rackunit
   racket/contract/base
            "../../src/errors/error-type.rkt"
         "../../src/machine/directories.rkt")

(module+ test
  (require rackunit
           "../../src/errors/error-type.rkt")

  ;; (listof (cons bytes bytes)) -> environment-variables, controlled env:
  ;; XDG_* from the cases below, HOME always set, PATH passed through so
  ;; the nu binary stays findable in the cross-language test
  (define (test-env pairs)
    (define ev (environment-variables-copy (current-environment-variables)))
    (for ([p (in-list pairs)])
      (environment-variables-set! ev (car p) (cdr p)))
    ev)

  (define ev-full
    (test-env (list (cons #"XDG_CONFIG_HOME" #"/tmp/pm-scope/config")
                    (cons #"XDG_CACHE_HOME" #"/tmp/pm-scope/cache")
                    (cons #"XDG_DATA_HOME" #"/tmp/pm-scope/data")
                    (cons #"HOME" #"/tmp/pm-scope/home"))))

  ;; XDG set: used verbatim.
  (check-equal?
   (parameterize ([current-environment-variables ev-full])
     (map path->string
          (list (roots-config (scope-roots 'user))
                (roots-cache (scope-roots 'user))
                (roots-data (scope-roots 'user)))))
   '("/tmp/pm-scope/config" "/tmp/pm-scope/cache" "/tmp/pm-scope/data"))

  ;; XDG unset: HOME fallbacks. The live environment carries real
  ;; XDG_CONFIG_HOME and XDG_DATA_HOME, so they are explicitly removed
  ;; here (#f unbinds); otherwise the test would measure the room, not
  ;; the fallback.
  (define ev-home-only
    (test-env (list (cons #"XDG_CONFIG_HOME" #f)
                    (cons #"XDG_CACHE_HOME" #f)
                    (cons #"XDG_DATA_HOME" #f)
                    (cons #"HOME" #"/tmp/pm-scope/home"))))
  (check-equal?
   (parameterize ([current-environment-variables ev-home-only])
     (map path->string
          (list (roots-config (scope-roots 'user))
                (roots-cache (scope-roots 'user))
                (roots-data (scope-roots 'user)))))
   '("/tmp/pm-scope/home/.config"
     "/tmp/pm-scope/home/.cache"
     "/tmp/pm-scope/home/.local/share"))

  ;; Blank counts as unset, like the Nu side.
  (define ev-blank
    (test-env (list (cons #"XDG_CACHE_HOME" #"   ")
                    (cons #"HOME" #"/tmp/pm-scope/home"))))
  (check-equal?
   (parameterize ([current-environment-variables ev-blank])
     (path->string (roots-cache (scope-roots 'user))))
   "/tmp/pm-scope/home/.cache")

  ;; Anything but user scope is deferred, kind 'config.
  (check-pred config-error?
              (with-handlers ([exn:fail:pm? (lambda (e) e)])
                (scope-roots 'system)
                'no-error))

  ;; Both implementations resolve identical roots for the user scope:
  (check-equal?
   (parameterize ([current-environment-variables ev-full])
     (map path->string
          (list (roots-config (scope-roots (quote user)))
                (roots-cache (scope-roots (quote user)))
                (roots-data (scope-roots (quote user))))))
   (list "/tmp/pm-scope/config" "/tmp/pm-scope/cache" "/tmp/pm-scope/data"))

  ;; G-06: explicit dirs first in order, then config, then data. No
  ;; network source exists anywhere in the answer.
  (check-equal?
   (parameterize ([current-environment-variables ev-full])
     (map path->string (spec-search-roots '("/x/specs" "/y/specs"))))
   '("/x/specs" "/y/specs"
     "/tmp/pm-scope/config/aiu-pm/specs"
     "/tmp/pm-scope/data/aiu-pm/specs"))
  ;; Duplicates collapse, order kept; empty explicit still yields the two.
  (check-equal?
   (parameterize ([current-environment-variables ev-full])
     (map path->string
          (spec-search-roots '("/x/specs" "/x/specs"))))
   '("/x/specs"
     "/tmp/pm-scope/config/aiu-pm/specs"
     "/tmp/pm-scope/data/aiu-pm/specs"))
  (check-equal?
   (parameterize ([current-environment-variables ev-full])
     (map path->string (spec-search-roots '())))
   '("/tmp/pm-scope/config/aiu-pm/specs"
     "/tmp/pm-scope/data/aiu-pm/specs")))

