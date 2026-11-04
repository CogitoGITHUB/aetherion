#lang racket/base
(require "../errors/err.rkt"
         "../errors/raise.rkt")

(provide home-dir
         xdg-config-home
         xdg-state-home
         xdg-cache-home
         xdg-runtime-dir)

(define (home-dir)
  (define h (getenv "HOME"))
  (if (and (string? h) (not (blank-string? h)))
      h
      (raise-error "HOME is not set"
                   "machine/directories home-dir"
                   "the environment"
                   "no HOME means no honest place for config, state or locks"
                   #:rule 'directories/home-required)))

(define (xdg variable default)
  (define v (getenv variable))
  (if (and (string? v) (not (blank-string? v))) v default))

(define (xdg-config-home)
  (xdg "XDG_CONFIG_HOME" (build-path (home-dir) ".config")))

(define (xdg-state-home)
  (xdg "XDG_STATE_HOME" (build-path (home-dir) ".local" "state")))

(define (xdg-cache-home)
  (xdg "XDG_CACHE_HOME" (build-path (home-dir) ".cache")))

(define (xdg-runtime-dir)
  (define v (getenv "XDG_RUNTIME_DIR"))
  (define t (getenv "TMPDIR"))
  (cond
    [(and (string? v) (not (blank-string? v))) v]
    [(and (string? t) (not (blank-string? t))) t]
    [else "/tmp"]))
