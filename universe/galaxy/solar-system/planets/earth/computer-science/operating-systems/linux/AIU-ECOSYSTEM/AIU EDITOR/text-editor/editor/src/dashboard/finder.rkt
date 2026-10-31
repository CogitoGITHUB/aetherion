#lang racket/base
;; One job: the finder. It runs fzf over a scope (the file, the project or the
;; workspace) for one kind of search (text, block types, todos or file names). The
;; rows show paths relative to the folder searched, and a preview at the top
;; shows the page formatted, or the file around the picked line. The terminal is given back to fzf while it
;; runs and taken again after it; a pick opens as a tab and the point jumps to its
;; line. Nothing is searched in a paint, and fzf is loaded only when a find key is
;; pressed.

(require racket/list
         racket/string
         racket/path
         "../commands/commands.rkt"
         "../machine/terminal.rkt"
         "tabs.rkt")

;; find-jump holds the line the next opened file jumps to, or nothing.
(define find-jump (box #f))

;; globs-skipped are the folders the finder never searches, as rg options.
(define globs-skipped
  "-g \"!.git\" -g \"!compiled\" -g \"!target\" -g \"!node_modules\" -g \"!aiu-compiled\"")

;; preview-path is where the preview script is written while fzf runs.
(define preview-path "/tmp/aiu-find-preview.sh")

;; preview-script answers the text of the preview program. A page (.aiu) is drawn by
;; the notation binary at the width of the preview, the way the editor draws it; any
;; other file shows the lines around the picked line with their numbers and a mark on
;; the picked one, or its head when the row has no line.
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

;; finder-script answers the shell text of one search: it goes to the folder, lists
;; the candidates with rg and hands them to fzf with the preview. The folder is the
;; first argument and the file name the second.
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

;; run-picker gives the terminal to fzf and answers what was picked, or an empty
;; text. The screen and the settings of the terminal are put back after it.
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
  (display "\u001b[?1049h\u001b[?25l")
  (flush-output)
  text)

;; parse-pick answers the complete path and the line of a pick: a row of rg is the
;; path, the line and the text; a file name is the path alone.
(define (parse-pick dir text)
  (define m (regexp-match #rx"^(.*?):([0-9]+):" text))
  (define rel (if m (cadr m) text))
  (values (path->complete-path rel dir)
          (and m (string->number (caddr m)))))

;; line-start-offset answers the byte offset of the start of a line of a text, the
;; first line being 1.
(define (line-start-offset text n)
  (let loop ([ls (string-split text "\n" #:trim? #f)] [k 1] [at 0])
    (if (or (null? ls) (>= k n))
        at
        (loop (cdr ls) (add1 k) (+ at (bytes-length (string->bytes/utf-8 (car ls))) 1)))))

;; scope-dir answers the folder a scope searches for the file of a session.
(define (scope-dir scope file root)
  (cond
    [(string=? scope "file") (or (path-only (string->path file)) (current-directory))]
    [(string=? scope "project") (tb-project-dir file root)]
    [else root]))

;; notation-bin answers the notation binary: the one AIU_NOTATION_BIN names, else the
;; one built under the notation project beside the workspace root.
(define (notation-bin root)
  (define named (getenv "AIU_NOTATION_BIN"))
  (if (and named (not (string=? named "")))
      named
      (path->string
       (build-path root "AIU NOTATION" "notation system" "notation" "target" "debug" "notation"))))

;; find-run runs one search and opens the pick as a tab. A pick ends the round of
;; the live session, which then opens the file and jumps to the line.
(define (find-run session scope kind)
  (define file (path->string (path->complete-path (session-file session))))
  (define root (tb-root file))
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

;; make-find answers the command of one scope and one kind.
(define (make-find scope kind)
  (lambda (session words) (find-run session scope kind)))

;; command-find-mode enters the find layer.
(define (command-find-mode session words)
  (set-layer! session "find")
  (cons #t "layer: find"))

;; The commands are added to the command table when this module is loaded, so the
;; keys find them and the gate sees the same table the editor does.
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

;; The finder, for the live session above it.
(provide find-jump
         line-start-offset)
