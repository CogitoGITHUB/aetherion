#lang racket/base

(require json
         racket/file
         racket/list
         racket/path
         racket/port
         racket/string
         "../checkpoint/checkpoint.rkt"
         "../machine/directories-shared.rkt"
         "../narration/events-shared.rkt"
         "../send/opencode-adapter.rkt")

(define audit-dir
  (build-path (state-dir) "audit"))

(define audit-log
  (build-path audit-dir "marks.jsonl"))

(define (make-mark path who session-id checkpoint)
  (hash 'path (path->string path)
        'who who
        'session session-id
        'checkpoint checkpoint
        'utc (utc-now)
        'hash-before (file-hash-at checkpoint path)
        'hash-after (file-hash path)))

(define (write-mark mark)
  (ensure-dir audit-dir)
  (call-with-output-file audit-log
    (lambda (port)
      (write-json mark port)
      (newline port))
    #:exists 'append)
  mark)

(define (audit-marks)
  (if (file-exists? audit-log)
      (filter values
              (for/list ([line (in-list (read-lines audit-log))])
                (with-handlers ([exn:fail? (lambda (why) #f)])
                  (read-json (open-input-string line)))))
      '()))

(define (read-lines path)
  (call-with-input-file path
    (lambda (port)
      (let loop ([out '()])
        (define line (read-line port))
        (if (eof-object? line)
            (reverse out)
            (loop (cons line out)))))))

(define (observe-changes root checkpoint client session-id)
  (define reported (agent-reported-files client session-id))
  (for/list ([path (in-list (changed-files root checkpoint))])
    (write-mark
     (make-mark (build-path root path)
                (if (member path reported) "agent" "external")
                session-id
                checkpoint))))

(define (agent-reported-files client session-id)
  (if (not session-id)
      '()
      (remove-duplicates
       (append* (for/list ([ask (in-list (client-permissions client session-id))])
                  (ask-files ask))))))

(define (changed-files root checkpoint)
  (if (or (string=? checkpoint "") (not (git-ok? root "cat-file" "-e" checkpoint)))
      '()
      (append (changed-tracked root checkpoint)
              (untracked-files root))))

(define (changed-tracked root checkpoint)
  (filter (lambda (line) (not (string=? line "")))
          (string-split (run-git root "diff" "--name-only" checkpoint) "\n")))

(define (file-hash path)
  (if (file-exists? path)
      (string-trim (run-git (tree-root path) "hash-object" path))
      ""))

(define (file-hash-at checkpoint path)
  (if (or (string=? checkpoint "") (not (file-exists? path)))
      ""
      (string-trim (run-git (tree-root path) "rev-parse"
                             (string-append checkpoint ":" (path-relative path))))))

(define (path-relative path)
  (define root (simplify-path (tree-root path)))
  (define root-text (string-append (path->string root) "/"))
  (define full (path->string (simplify-path (path->complete-path path))))
  (if (starts-with? full root-text)
      (substring full (string-length root-text))
      full))

(define (starts-with? text prefix)
  (and (>= (string-length text) (string-length prefix))
       (string=? (substring text 0 (string-length prefix)) prefix)))

(provide path-relative
         audit-dir
         audit-log
         make-mark
         write-mark
         audit-marks
         observe-changes
         agent-reported-files
         changed-files
         file-hash
         file-hash-at)
