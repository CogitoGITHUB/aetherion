#lang racket/base

(require racket/list
         racket/string
         racket/path
         "../../commands/commands-shared.rkt"
         "../../machine/terminal.rkt" (only-in "../../drawing/screen-diff.rkt" screen-forget!)
         "tabs-shared.rkt")

(define find-jump (box #f))

;; globs-skipped are the folders the finder never searches, as rg options.
(define globs-skipped
  "-g \"!.git\" -g \"!compiled\" -g \"!target\" -g \"!node_modules\" -g \"!aiu-compiled\"")

(define preview-path "/tmp/aiu-find-preview.sh")

(define preview-script
  (string-join
   (list "f=\"$1\""
         "n=\"$2\""
         "if [ ! -f \"$f\" ]; then exit 0; fi"
         "w=$((${FZF_PREVIEW_COLUMNS:-80}-4))"
         "case \"$f\" in"
         "  *.aiu) if [ -x \"$AIU_PREVIEW_NB\" ]; then \"$AIU_PREVIEW_NB\" view \"$f\" --width \"$w\"; exit 0; fi;;"
         "esac"
         "case \"$n\" in"
         "  \"\") head -n 40 \"$f\"; exit 0;;"
         "  *[!0-9]*) head -n 40 \"$f\"; exit 0;;"
         "esac"
         "s=$((n-4))"
         "if [ \"$s\" -lt 1 ]; then s=1; fi"
         "e=$((n+30))"
         "sed -n \"${s},${e}p\" \"$f\" | sed -e \"s/^/  /\" -e \"$((n-s+1))s/^  />> /\" | nl -ba -v \"$s\" -w 4 -s \" \""
         "")
   "\n"))

(define (finder-script scope kind)
  (define file? (string=? scope "file"))
  (define target (if file? "\"$2\"" "."))
  (define named (if file? "--with-filename " ""))
  (define skips (if file? "" (string-append globs-skipped " ")))
  (define aiu (if file? "" "-g \"*.aiu\" "))
  (define base (string-append "rg -n --no-heading --color never --hidden " named skips))
  (define search
    (cond
      [(string=? kind "text") (string-append base "\".\" " target)]
      [(string=? kind "blocks") (string-append base aiu "\"^[a-z][a-z-]* start\\$\" " target)]
      [(string=? kind "todos") (string-append base aiu "\"^todo:\" " target)]
      [else (string-append "rg --files --hidden " globs-skipped " .")]))
  (string-append "cd \"$1\" && " search
                 " | fzf --prompt \"" scope " " kind "> \" --delimiter : --preview \"sh "
                 preview-path " {1} {2}\" --preview-window \"up,60%,wrap\""))

(define (run-picker dir name script)
  (call-with-output-file preview-path #:exists (quote truncate)
    (lambda (p) (write-string preview-script p)))
  (restore-settings)
  (display "\u001b[?25h\u001b[?1049l")
  (flush-output)
  (define errp (and (file-stream-port? (current-error-port)) (current-error-port)))
  (define text
    (with-handlers ([(lambda (e) #t) (lambda (e) "")])
      (let-values ([(sp out in err) (subprocess #f #f errp "/bin/sh" "-c" script "sh" dir name)])
        (close-output-port in)
        (let ([s (read-string 1000000 out)])
          (close-input-port out)
          (when err (close-input-port err))
          (subprocess-wait sp)
          (if (string? s) (string-trim s) "")))))
  (with-handlers ([(lambda (e) #t) void]) (delete-file preview-path))
  (raw-mode)
  (screen-forget!)
  (display "\u001b[?1049h\u001b[?25l")
  (flush-output)
  text)

(define (parse-pick dir text)
  (define m (regexp-match #rx"^(.*?):([0-9]+):" text))
  (define rel (if m (cadr m) text))
  (values (path->complete-path rel dir)
          (and m (string->number (caddr m)))))

(define (line-start-offset text n)
  (let loop ([ls (string-split text "\n" #:trim? #f)] [k 1] [at 0])
    (if (or (null? ls) (>= k n))
        at
        (loop (cdr ls) (add1 k) (+ at (bytes-length (string->bytes/utf-8 (car ls))) 1)))))

(define (scope-dir scope file root)
  (cond
    [(string=? scope "file") (or (path-only (string->path file)) (current-directory))]
    [(string=? scope "project") (tabs-project-dir file root)]
    [else root]))

(require "../../bridge/location.rkt")

(define (notation-bin root)
  (or (notation-bin-from root) (path->string (apply build-path root notation-tail))))

(define (find-run session scope kind)
  (define file (path->string (path->complete-path (session-file session))))
  (define root (tabs-root file))
  (define dir (scope-dir scope file root))
  (define name (let ([n (file-name-from-path file)]) (if n (path->string n) file)))
  (set-layer! session "visual")
  (cond
    [(not (find-executable-path "fzf")) (cons #t "fzf is not installed")]
    [else
     (putenv "AIU_PREVIEW_NB" (notation-bin root))
     (define text (run-picker (path->string dir) name (finder-script scope kind)))
     (cond
       [(string=? text "") (cons #t "nothing picked")]
       [else
        (define-values (target line) (parse-pick dir text))
        (cond
          [(file-exists? target)
           (tab-show! (path->string target))
           (set-box! find-jump line)
           (set-box! tab-switch (path->string target))
           (cons #f "")]
          [else (cons #t "that file is not there")])])]))

(define (make-find scope kind)
  (lambda (session words) (find-run session scope kind)))

(define (command-find-mode session words)
  (set-layer! session "find")
  (cons #t "layer: find"))

(hash-set! commands "find-mode" command-find-mode)
(hash-set! commands "find-file-text" (make-find "file" "text"))
(hash-set! commands "find-file-blocks" (make-find "file" "blocks"))
(hash-set! commands "find-file-todos" (make-find "file" "todos"))
(hash-set! commands "find-project-text" (make-find "project" "text"))
(hash-set! commands "find-project-blocks" (make-find "project" "blocks"))
(hash-set! commands "find-project-todos" (make-find "project" "todos"))
(hash-set! commands "find-project-files" (make-find "project" "files"))
(hash-set! commands "find-workspace-text" (make-find "workspace" "text"))
(hash-set! commands "find-workspace-blocks" (make-find "workspace" "blocks"))
(hash-set! commands "find-workspace-todos" (make-find "workspace" "todos"))
(hash-set! commands "find-workspace-files" (make-find "workspace" "files"))

(provide find-jump
         line-start-offset)