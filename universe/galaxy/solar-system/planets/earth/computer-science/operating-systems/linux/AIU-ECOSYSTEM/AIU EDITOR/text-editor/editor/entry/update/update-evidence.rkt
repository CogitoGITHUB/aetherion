#lang racket/base
(require racket/system racket/string racket/list racket/file racket/path "update-table.rkt" "update-screen.rkt")

(define last-evidence (box (list)))

(define (count-bytes pat raw)
  (length (regexp-match* (byte-regexp (regexp-quote pat)) raw)))

(define (trace-tail start n)
  (with-handlers ([void (lambda (e) (list "    trace of this run: unreadable"))])
    (let* ([bs (call-with-input-file (trace-file) (lambda (i) (file-position i start) (read-bytes 100000 i)))]
           [ls (if (bytes? bs) (string-split (bytes->string/utf-8 bs #\?) "\n") (list))])
      (cons (format "    trace of this run, last ~a of ~a lines (go-on #f ends a session):" n (length ls))
            (map (lambda (l)
                   (define m (regexp-match #px"^[0-9.]+ act-on ([0-9]+)[0-9.]* ms pending (.*) go-on (.*)$" l))
                   (string-append "    t " (if m (format "keys ~a ~ams go-on ~a" (caddr m) (cadr m) (cadddr m)) l)))
                 (last-n ls n))))))

(define (key-frame-has? dir i txt)
  (define raw (with-handlers ([void (lambda (e) #"")]) (file->bytes (build-path dir (format "s~a.bin" i)))))
  (regexp-match? (regexp-quote txt) (plain-screen (last-frame (bytes->string/utf-8 raw #\?)))))

(define (key-heads dir names)
  (for/list ([n (in-list names)] [i (in-naturals 0)])
    (define raw (with-handlers ([void (lambda (e) #"")]) (file->bytes (build-path dir (format "s~a.bin" i)))))
    (define scr (plain-screen (last-frame (bytes->string/utf-8 raw #\?))))
    (define ls
      (filter (lambda (l) (regexp-match? #px"[A-Za-z]{3}" l))
              (map (lambda (l) (string-trim (regexp-replace* #px"[│╭╮╰╯├┤┬┴┼─●]+" l " "))) (string-split scr "\n"))))
    (format "    screen after ~a ~a: ~a" i n
            (string-join (map (lambda (l) (if (> (string-length l) 28) (substring l 0 28) l)) (first-n ls 3)) " / "))))

(define (evidence-lines dir out lines verdicts screen trace-start)
  (define raw (with-handlers ([void (lambda (e) #"")]) (file->bytes out)))
  (define text (bytes->string/utf-8 raw #\?))
  (define code (with-handlers ([void (lambda (e) "unknown")]) (string-trim (file->string (build-path dir "code.txt")))))
  (define starts (count-bytes (bytes-append (bytes 27) #"[?1049h") raw))
  (define ends (count-bytes (bytes-append (bytes 27) #"[?1049l") raw))
  (define parts (let ([p (regexp-split (regexp-quote "\u001b[?2026h") text)]) (if (pair? p) (cdr p) p)))
  (define odd (filter (lambda (p) (not (regexp-match? #rx"^\u001b\\[H" p))) parts))
  (define last-odd? (and (pair? parts) (not (regexp-match? #rx"^\u001b\\[H" (last parts)))))
  (define names (string-split (string-join (line-values lines "keys") " ")))
  (define everything (plain-screen text))
  (define no-fail? (andmap car verdicts))
  (define missing
    (for/list ([v (in-list verdicts)] #:when (and (not (car v)) (regexp-match? #px"^screen contains " (cadr v))))
      (substring (cadr v) (string-length "screen contains "))))
  (define lacks-failed?
    (for/or ([v (in-list verdicts)]) (and (not (car v)) (regexp-match? #px"^screen lacks " (cadr v)))))
  (define key-rows (map (lambda (l) (string-append "    " (string-trim (car (regexp-split #rx" [|] " l))))) (key-modes dir names)))
  (define frame-rows
    (for/list ([ip (in-list (last-n (for/list ([p (in-list parts)] [i (in-naturals 1)]) (cons i p)) 8))])
      (define t (plain-screen (cdr ip)))
      (define m (regexp-match #px"╭─ ([a-z]+( [a-z]+)?) \\[" t))
      (format "    frame ~a starts ~a len ~a mode ~a" (car ip) (visible (substring (cdr ip) 0 (min 6 (string-length (cdr ip))))) (string-length t) (if m (cadr m) "none"))))
  (define missing-lines
    (for/list ([t (in-list missing)])
      (define after (for/list ([n (in-list names)] [i (in-naturals 0)] #:when (key-frame-has? dir i t)) (format "~a ~a" i n)))
      (format "    expected text ~s: seen after keys [~a]; anywhere in the output: ~a" t (string-join after ", ") (if (regexp-match? (regexp-quote t) everything) "yes" "NO, never drawn"))))
  (define next
    (cond
      [(not (equal? code "0")) (string-append "    NEXT: the run ended with " code ", not 0: read the cause line, then the trace and the last frames above")]
      [last-odd? "    NEXT: the final frame does not start with ESC[H, so last-frame skips it and the report shows an older screen: fix last-frame in update.rkt"]
      [(for/or ([t (in-list missing)]) (not (regexp-match? (regexp-quote t) everything)))
       "    NEXT: an expected text was never drawn in this run: read the key bindings, the mode rows and the trace above"]
      [(pair? missing) "    NEXT: the expected text was drawn after some key but is gone at the end: a later key or session replaced it, see the seen after keys lists"]
      [lacks-failed? "    NEXT: a text that must be gone is still on the last frame: the key that should remove it did nothing, see the mode rows and the trace"]
      [no-fail? (format "    NEXT: nothing failed to draw; sessions started ~a, ended ~a. If the keys should open another page and only one session started, no page opened: read the go-on values in the trace" starts ends)]
      [else "    NEXT: read the failed lines above against the screen seen"]))
  (append
   (list (format "    evidence: sessions started ~a, ended ~a, frames drawn ~a, frames without ESC[H start ~a, exit ~a" starts ends (length parts) (length odd) code)
         "    frames per key and the mode after it:")
   key-rows
   (key-heads dir names)
   (list "    last frames of the whole run:")
   frame-rows
   missing-lines
   (trace-tail trace-start 20)
   (list next)))


(provide last-evidence count-bytes trace-tail key-frame-has? key-heads evidence-lines)
