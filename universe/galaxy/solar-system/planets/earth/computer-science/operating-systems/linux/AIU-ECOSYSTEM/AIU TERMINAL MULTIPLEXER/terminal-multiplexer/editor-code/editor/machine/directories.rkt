#lang racket/base

(require racket/file
         racket/path
         racket/string
         "../errors/raise.rkt")

(define (home-dir)
  (define h (getenv "HOME"))
  (if (or (not h) (string=? h ""))
      (error-of 'err-no-home "the editor" "the home directory"
                "HOME is not set" "set HOME to the home directory and run again")
      (path->complete-path h)))

(define (xdg-dir kind fallback)
  (define value (getenv (string-append "XDG_" (string-upcase kind) "_HOME")))
  (if (and value (not (string=? value "")))
      (path->complete-path value)
      (apply build-path (home-dir) fallback)))

(define (config-dir)
  (build-path (xdg-dir "config" '(".config")) "aiu-editor"))

(define (state-dir)
  (build-path (xdg-dir "state" '(".local" "share")) "aiu-editor"))

(define (cache-dir)
  (build-path (xdg-dir "cache" '(".cache")) "aiu-editor"))

(define (racket-bin)
  (define named (getenv "AIU_RACKET_BIN"))
  (define bin (if (and named (not (string=? named "")))
                  (path->complete-path named)
                  (build-path (home-dir) "opt" "racket-full" "bin" "racket")))
  (if (file-exists? bin)
      bin
      (error-of 'err-no-racket "the editor" (path->string bin)
                "the Racket program is not there"
                "set AIU_RACKET_BIN to the racket program, or put Racket under the home directory")))

(define (git-bin)
  (define named (getenv "AIU_GIT_BIN"))
  (define bin (if (and named (not (string=? named "")))
                  (path->complete-path named)
                  "/usr/bin/git"))
  (if (file-exists? bin)
      bin
      (error-of 'err-no-git "the editor" (path->string bin)
                "the git program is not there"
                "set AIU_GIT_BIN to the git program, or put git where the editor looks")))

(define (hot-path-bin)
  (define named (getenv "AIU_HOT_PATH_BIN"))
  (define bin (if (and named (not (string=? named "")))
                  (path->complete-path named)
                  (build-path (find-system-path (quote home-dir)) "aiu-cargo-target" "debug" "hot-path")))
  (if (file-exists? bin)
      bin
      (error-of 'err-no-hot-path "the editor" (path->string bin)
                "the hot path program is not there"
                "build the editor crate, or set AIU_HOT_PATH_BIN to the hot path program")))

(define (crate-dir)
  (define named (getenv "AIU_EDITOR_CRATE"))
  (if (and named (not (string=? named "")))
      (path->complete-path named)
      (let loop ([at (simplify-path (current-directory))])
        (define up (simplify-path (build-path at "..")))
        (define candidates (list (build-path at "editor") at))
        (define found (for/or ([candidate (in-list candidates)])
                        (and (file-exists? (build-path candidate "Cargo.toml"))
                             candidate)))
        (cond
          [found found]
          [(string=? (path->string at) (path->string up)) (car candidates)]
          [else (loop up)]))))

(define (target-dir)
  (define named (getenv "AIU_CARGO_TARGET_DIR"))
  (if (and named (not (string=? named "")))
      (path->complete-path named)
      (simplify-path (build-path (hot-path-bin) "../.."))))

(define (journal-path-for path)
  (build-path (state-dir) "journal"
              (format "~a-~a.journal" (file-name-from-path path) (path-key path))))

(define (path-key path)
  (let loop ([chars (string->list (path->string path))] [sum 0])
    (if (null? chars)
        (format "~a" (modulo sum 100000))
        (loop (cdr chars) (+ sum (char->integer (car chars)))))))

(define (ensure-dir d)
  (cond
    [(directory-exists? d) d]
    [else
     (with-handlers
         ([exn:fail?
           (lambda (e)
             (error-of 'err-no-directory "the editor" (path->string d)
                       "the directory could not be created"
                       "check the permissions of the directory above it"))])
       (make-directory* d)
       d)]))

(provide home-dir
         xdg-dir
         config-dir
         state-dir
         cache-dir
         racket-bin
         git-bin
         hot-path-bin
         crate-dir
         target-dir
         journal-path-for
         ensure-dir)
