#lang racket/base

(require json
         racket/file
         racket/list
         racket/path
         racket/port
         racket/string
         racket/system
         "../editor/entry/capabilities.rkt"
         "../editor/entry/dispatch/dispatch.rkt"
         "../editor/entry/documents.rkt"
         "../editor/entry/mcp.rkt"
         "../editor/machine/directories.rkt"
         "../editor/narration/wait-door.rkt")

(define project-dir
  (let loop ([at (simplify-path (current-directory))])
    (define up (simplify-path (build-path at "..")))
    (cond
      [(and (directory-exists? (build-path at "editor"))
            (directory-exists? (build-path at "gate")))
       at]
      [(string=? (path->string at) (path->string up)) at]
      [else (loop up)])))

(define cli-path
  (build-path project-dir "editor" "entry" "cli.rkt"))

(define skill-path
  (build-path (build-path project-dir "..") "agent" "skills" "editor" "SKILL.md"))

(define plugin-path
  (build-path (build-path project-dir "..") "agent" "opencode-plugin" "editor-watch.js"))

(define scratch-dir
  (build-path (or (getenv "TMPDIR") "/tmp") "aiu-kit-check"))

(define token "kit-check-token")

(define (main)
  (ensure-dir scratch-dir)
  (putenv "AIU_EDITOR_TOKEN" token)
  (define problems '())
  (set! problems (append problems (proof-envelope)))
  (set! problems (append problems (proof-exit-codes)))
  (set! problems (append problems (proof-gating)))
  (set! problems (append problems (proof-skill)))
  (set! problems (append problems (proof-plugin)))
  (set! problems (append problems (proof-feed-and-door)))
  (if (null? problems)
      (begin
        (displayln "OK kit-check — the six proofs hold: the one envelope, the frozen codes, the gating, the skill examples, the read-only plugin, and the flushed feed with the wait door held")
        (exit exit-ok))
      (begin
        (for ([problem (in-list problems)]) (displayln (format "KIT — ~a" problem)))
        (displayln (format "KIT — ~a of the six proofs do not hold" (length problems)))
        (exit exit-cannot-run))))

(define (proof-envelope)
  (define problems '())
  (define env
    (envelope-in
     (handle-request
      (json-text (hash 'jsonrpc "2.0" 'id 1 'method "tools/call"
                        'params (hash 'name "routes" 'arguments (hash)))))))
  (if (not env)
      (set! problems (cons "the MCP did not answer in the one envelope" problems))
      (begin
        (for ([field (in-list '(program version kind ok data refusal events))])
          (unless (hash-has-key? env field)
            (set! problems (cons (format "the envelope has no ~a field" field) problems))))
        (unless (string=? (hash-ref env 'program "") program-name)
          (set! problems (cons "the envelope names another program" problems)))
        (unless (hash-ref env 'ok #f)
          (set! problems (cons "the envelope says the read did not answer" problems)))))
  (define cli-text (capture (lambda () (run-verb "routes" '()))))
  (if (and env (hash? (hash-ref env 'data #f)))
      (unless (string=? (hash-ref (hash-ref env 'data) 'text "") cli-text)
        (set! problems (cons "the CLI and the MCP did not answer with the same text" problems)))
      (set! problems (cons "the envelope carries no data to compare with the CLI" problems)))
  problems)

(define (proof-exit-codes)
  (define problems '())
  (unless (and (= exit-ok 0) (= exit-refusal 2) (= exit-cannot-run 3))
    (set! problems (cons "the exit codes are not the frozen ones" problems)))
  (define code
    (run-code (format "~a ~a no-such-verb >/dev/null 2>&1"
                       (racket-bin) (shell-quote (path->string cli-path)))))
  (unless (= code exit-refusal)
    (set! problems (cons (format "the CLI refused with code ~a, and the frozen refusal code is ~a"
                                 code exit-refusal)
                          problems)))
  (define refused
    (envelope-in
     (handle-request
      (json-text (hash 'jsonrpc "2.0" 'id 2 'method "tools/call"
                        'params (hash 'name "send" 'arguments (hash)))))))
  (if (and refused (hash? (hash-ref refused 'refusal #f)))
      (unless (not (string=? (hash-ref (hash-ref refused 'refusal) 'rule "") ""))
        (set! problems (cons "the refusal names no rule" problems)))
      (set! problems (cons "the MCP's refusal carried no rule" problems)))
  problems)

(define (proof-gating)
  (define problems '())
  (define without
    (envelope-in
     (handle-request
      (json-text (hash 'jsonrpc "2.0" 'id 3 'method "tools/call"
                        'params (hash 'name "checkpoint" 'arguments (hash)))))))
  (if (and without (not (hash-ref without 'ok #f)))
      (unless (not (string=? (hash-ref (hash-ref without 'refusal #f) 'rule "") ""))
        (set! problems (cons "the refusal without the token names no rule" problems)))
      (set! problems (cons "a change without the human's token was not refused" problems)))
  (define wrong
    (envelope-in
     (handle-request
      (json-text (hash 'jsonrpc "2.0" 'id 4 'method "tools/call"
                        'params (hash 'name "checkpoint"
                              'arguments (hash 'confirm "not-the-token")))))))
  (if (and wrong (not (hash-ref wrong 'ok #f)))
      #t
      (set! problems (cons "a change with the wrong token was not refused" problems)))
  (define right
    (envelope-in
     (handle-request
      (json-text (hash 'jsonrpc "2.0" 'id 5 'method "tools/call"
                        'params (hash 'name "stop"
                              'arguments (hash 'args '("start") 'confirm token)))))))
  (if (and right (hash-ref right 'ok #f))
      #t
      (set! problems (cons "a change with the human's token was refused anyway" problems)))
  (define liar (declaration-honest?))
  (if liar
      (set! problems (cons (format "the declaration lies about ~a" liar) problems))
      #t)
  (unless (string-contains? (file->string (build-path project-dir "editor" "entry" "mcp.rkt"))
                             "declaration-agrees?")
    (set! problems (cons "the server does not re-check the declaration" problems)))
  problems)

(define (proof-skill)
  (define problems '())
  (define examples (skill-examples))
  (if (null? examples)
      (set! problems (cons "the skill holds no example to run" problems))
      (for ([example (in-list examples)])
        (define code (run-code example))
        (unless (= code 0)
          (set! problems (cons (format "the example did not answer: ~a (code ~a)" example code)
                               problems)))))
  problems)

(define (run-code command)
  (define code-file (build-path scratch-dir "exit-code"))
  (when (file-exists? code-file) (delete-file code-file))
  (system (format "~a; echo $? > ~a 2>/dev/null"
                  command (shell-quote (path->string code-file))))
  (if (file-exists? code-file)
      (string->number (string-trim (file->string code-file)))
      #f))

(define (starts-with? text prefix)
  (and (>= (string-length text) (string-length prefix))
       (string=? (substring text 0 (string-length prefix)) prefix)))

(define (skill-examples)
  (for/list ([line (in-list (lines-of skill-path))]
             #:when (starts-with? (string-trim line) "racket "))
    (define trimmed (string-trim line))
    (format "cd ~a && ~a ~a >/dev/null 2>&1"
            (shell-quote (path->string project-dir))
            (shell-quote (path->string (racket-bin)))
            (substring trimmed (string-length "racket ")))))

(define (proof-plugin)
  (define problems '())
  (define source (file->string plugin-path))
  (for ([call (in-list '("writeFileSync" "appendFileSync" "createWriteStream"
                          "unlinkSync" "rmSync" "mkdirSync" "renameSync"
                          "copyFileSync" "truncateSync" "chmodSync" "openSync"))])
    (when (string-contains? source call)
      (set! problems (cons (format "the plugin holds a write call: ~a" call) problems))))
  (define watched (build-path scratch-dir "watched.txt"))
  (call-with-output-file watched
    (lambda (port) (display "the first line\n" port))
    #:exists 'truncate)
  (define before (file->string watched))
  (define code
    (run-code (format "~a ~a ~a >/dev/null 2>&1"
                       (shell-quote (node-bin))
                       (shell-quote (path->string plugin-path))
                       (shell-quote (path->string watched)))))
  (unless (= code 0)
    (set! problems (cons "the plugin did not run" problems)))
  (unless (string=? before (file->string watched))
    (set! problems (cons "the plugin changed the file it watches" problems)))
  problems)

(define (node-bin)
  (define named (getenv "AIU_NODE_BIN"))
  (if (and named (not (string=? named "")))
      named
      (let ([found (find-executable-path "node")])
        (if found found "node"))))

(define (find-executable-path name)
  (define dirs (getenv "PATH"))
  (if (not dirs)
      #f
      (for/or ([dir (in-list (string-split dirs ":"))])
        (define candidate (build-path dir name))
        (and (file-exists? candidate) (path->string candidate)))))

(define (proof-feed-and-door)
  (define problems '())
  (define scratch (build-path scratch-dir "feed.txt"))
  (call-with-output-file scratch
    (lambda (port) (display "the first line\n" port))
    #:exists 'truncate)
  (define journal (journal-path-for scratch))
  (when (file-exists? journal) (delete-file journal))
  (define code
    (run-code (format "cd ~a && printf 'insert hello\\nshow\\nquit\\n' | ~a ~a edit ~a >/dev/null 2>&1"
                       (shell-quote (path->string project-dir))
                       (shell-quote (path->string (racket-bin)))
                       (shell-quote (path->string cli-path))
                       (shell-quote (path->string scratch)))))
  (unless (= code 0)
    (set! problems (cons "the session did not run, so the feed was not proved" problems)))
  (if (file-exists? journal)
      (let* ([text (file->string journal)]
             [whole (and (> (string-length text) 0)
                         (char=? (string-ref text (sub1 (string-length text))) #\newline))]
             [records (filter (lambda (line) (not (string=? line "")))
                               (string-split text "\n"))])
        (unless whole
          (set! problems (cons "the feed's last record is not whole: it was not flushed" problems)))
        (unless (> (length records) 0)
          (set! problems (cons "the feed holds no record" problems))))
      (set! problems (cons "the session left no feed behind" problems)))
  (unless (wait-refused "" "the event that ends it")
    (set! problems (cons "the wait door held a wait with no reason" problems)))
  (unless (wait-refused "the reason" "")
    (set! problems (cons "the wait door held a wait with no event" problems)))
  problems)

(define (wait-refused why on-event)
  (with-handlers ([exn:fail? (lambda (why) #t)])
    (capture (lambda () (wait-for "the kit check" "the feed" why on-event)))
    #f))

(define (capture work)
  (define out (open-output-string))
  (parameterize ([current-output-port out]) (work))
  (get-output-string out))

(define (json-text value)
  (define out (open-output-string))
  (write-json value out)
  (get-output-string out))

(define (shell-quote text)
  (string-append "'" (string-replace text "'" "'\\''") "'"))

(define (lines-of path)
  (with-handlers ([exn:fail? (lambda (why) '())])
    (call-with-input-file path
      (lambda (port)
        (let loop ([out '()])
          (define line (read-line port))
          (if (eof-object? line)
              (reverse out)
              (loop (cons line out))))))))

(module+ main
  (main))
