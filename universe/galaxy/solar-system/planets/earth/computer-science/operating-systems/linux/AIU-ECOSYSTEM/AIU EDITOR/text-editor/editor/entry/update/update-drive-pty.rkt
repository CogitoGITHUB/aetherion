#lang racket/base
;; One job: the pty driver: runs the editor in a terminal, sends one key per finished frame and saves what came out.
(require racket/system racket/string racket/list racket/file racket/path "update-table.rkt" "update-screen.rkt" "update-evidence.rkt" "update-drive-live.rkt")

;; drive-editor runs the editor in a pty, sends one key per finished frame, saves a snapshot after each key and the exit code.
(define (drive-editor dir copy chunks out out1 code-file)
  (define sh (find-executable-path "sh"))
  (define-values (sp so si se)
    (subprocess #f #f (quote stdout) sh "-c" (string-append "AIU_TRACE_FILE=\"" (path->string (trace-file)) "\" AIU_TRACE=1 exec script -qec \"aiutd " copy "\" /dev/null")))
  (define acc (open-output-bytes))
  (define marker (byte-regexp (regexp-quote (bytes-append (bytes 27) #"[?2026l"))))
  (define buf (make-bytes 4096))
  (define (trace-lines) (with-handlers ([void (lambda (e) 0)]) (length (regexp-match* (byte-regexp (bytes 10)) (file->bytes (trace-file))))))
  (define (frames) (length (regexp-match* marker (get-output-bytes acc))))
  (define (popup-last?)
    (define all (get-output-bytes acc))
    (define ps (regexp-match-positions* marker all))
    (and (pair? ps)
         (let* ([e (car (list-ref ps (- (length ps) 1)))]
                [s (if (null? (cdr ps)) 0 (cdr (list-ref ps (- (length ps) 2))))])
           (regexp-match? #rx"waiting after" (plain-screen (bytes->string/utf-8 (subbytes all s e) #\?))))))
  (define (wait-frame n [tl #f] [settle? #f])
    (define base #f)
    (define deadline (+ (current-inexact-milliseconds) 20000))
    (let loop ()
      (cond
        [(and tl (not base) (> (trace-lines) tl)) (set! base (frames)) (loop)]
        [(and (> (frames) n) (or (not tl) (and base (> (frames) base))) (or (not settle?) (not (popup-last?)))) #t]
        [else
         (define left (- deadline (current-inexact-milliseconds)))
         (cond
           [(<= left 0) #f]
           [(sync/timeout (/ left 1000.0) so)
            (define k (read-bytes-avail! buf so))
            (cond [(eof-object? k) #f]
                  [else (when (and tl (not base) (> (trace-lines) tl)) (set! base (frames))) (write-bytes buf acc 0 k) (loop)])]
           [else #f])])))
    ;; starts-now counts the times the editor entered its screen so far; every session enters once.
  (define (starts-now)
    (length (regexp-match* (byte-regexp (regexp-quote (bytes-append (bytes 27) #"[?1049h"))) (get-output-bytes acc))))

  ;; ends-now counts the times the editor left its screen so far.
  (define (ends-now)
    (length (regexp-match* (byte-regexp (regexp-quote (bytes-append (bytes 27) #"[?1049l"))) (get-output-bytes acc))))

  ;; key-line answers the trace line that the key sent at line count tl wrote, or false.
  (define (key-line tl)
    (with-handlers ([void (lambda (e) #f)])
      (let ([ls (string-split (file->string (trace-file)) "\n")])
        (and (> (length ls) tl) (list-ref ls tl)))))

  ;; frames-after-start counts the frames drawn since the last screen enter.
  (define (frames-after-start)
    (define all (get-output-bytes acc))
    (define ps (regexp-match-positions* (byte-regexp (regexp-quote (bytes-append (bytes 27) #"[?1049h"))) all))
    (if (null? ps) 0 (length (regexp-match* marker (subbytes all (cdr (last ps)))))))

  ;; wait-session answers true when the key did not end its session, when the next session has drawn its first frame, when the editor ended and no session followed within 2 s, or when a tab round in the same terminal went quiet.
  (define (wait-session s0 e0 tl)
    (define line (key-line tl))
    (cond
      [(not (and line (regexp-match? #rx"go-on #f( |$)" line))) #t]
      [else
       (define t-key (current-inexact-milliseconds))
       (define deadline (+ t-key 20000))
       (define left-at #f)
       (define last-data t-key)
       (let loop ()
         (define now (current-inexact-milliseconds))
         (when (and (not left-at) (> (ends-now) e0)) (set! left-at now))
         (cond
           [(and (> (starts-now) s0) (> (frames-after-start) 0)) #t]
           [(and left-at (= (starts-now) s0) (> (- now left-at) 2000)) #t]
           [(and (not left-at) (= (starts-now) s0) (> (- now t-key) 1200) (> (- now last-data) 400)) #t]
           [(> now deadline) #f]
           [(sync/timeout 0.2 so)
            (define k (read-bytes-avail! buf so))
            (cond [(eof-object? k) #t]
                  [else (write-bytes buf acc 0 k) (set! last-data now) (loop)])]
           [else (loop)]))]))

  (define (save-to path)
    (call-with-output-file path #:exists (quote truncate) (lambda (o) (write-bytes (get-output-bytes acc) o))))
  (define note
    (if (not (wait-frame 0))
        "none: no first frame in 20 s"
        (let loop ([cs chunks] [i 0])
          (cond
            [(null? cs) #f]
            [else
             (define n (frames))
             (define tl (trace-lines))
        (define s0 (starts-now))
        (define e0 (ends-now))
             (begin (live (format "send key ~a" i)) (write-string (car cs) si))
             (flush-output si)
             (cond
               [(and (wait-frame n tl) (wait-session s0 e0 tl))
                (begin (live (format "frame after key ~a" i)) (save-to (build-path dir (format "s~a.bin" i))))
                (loop (cdr cs) (+ i 1))]
               [else (live (format "NO FRAME after key ~a in 20 s" i)) (format "none: no frame after key ~a" i)])]))))
  (save-to out1)
  (begin (live "send q") (write-string "q" si))
  (flush-output si)
  (define done (begin (live "wait for exit, 15 s at most") (sync/timeout 15 sp)))
  (begin (live (if done "editor exited, draining output" "editor did not exit, killing it, draining output")) (unless done (subprocess-kill sp #t)))
  (let loop ()
    (when (sync/timeout 1 so)
      (define k (read-bytes-avail! buf so))
      (unless (eof-object? k)
        (write-bytes buf acc 0 k)
        (loop))))
  (begin (live "output drained, saving") (save-to out))
  (call-with-output-file code-file #:exists (quote truncate)
    (lambda (o) (write-string (or note (if done (number->string (subprocess-status sp)) "124")) o)))
  (close-output-port si)
  (close-input-port so))


(provide drive-editor)
