#lang racket/base
;; source-url-check.rkt -- the url check for lockfile and manifest entries:
;; a local: url (a folder on this machine, see local-source-pin.rkt) passes,
;; everything else must be a valid git URL. git/ and the vault keep the
;; strict check-git-url, so nothing local ever reaches a git command.

(require racket/contract/base
         racket/string
         "../git/git-env.rkt")

(provide
 (contract-out
  ;; string -> void, a local: url or a valid git URL, else a refusal
  [check-source-url (-> string? void?)]))

(define (check-source-url url)
  (unless (and (string-prefix? url "local:") (> (string-length url) 6))
    (check-git-url url)))
