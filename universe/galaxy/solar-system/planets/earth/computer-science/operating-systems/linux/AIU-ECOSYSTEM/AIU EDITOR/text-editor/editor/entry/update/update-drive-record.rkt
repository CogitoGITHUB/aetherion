#lang racket/base
(require racket/system racket/string racket/list racket/file racket/path "update-table.rkt" "update-screen.rkt" "update-evidence.rkt" "update-drive-run.rkt")

(define rec-why (box (list)))

(define (record-lines s0)
  (define s (regexp-replace* #px"[│╭╮╰╯├┤┬┴┼─]+" s0 " "))
  (remove-duplicates
   (filter (lambda (l) (and (>= (string-length l) 6) (<= (string-length l) 78) (regexp-match? #px"[A-Za-z]{3}" l) (regexp-match? #px"^[[:print:]]+$" l) (not (regexp-match? #px"[0-9]:[0-9][0-9]" l))))
           (map string-trim (string-split s "\n")))))

(define (no-change-why keys ksl bsl)
  (define src (build-path editor-root "editor"))
  (define src-text (path->string src))
  (define km (with-handlers ([void (lambda (e) (list))]) (append* (for/list ([p (in-list (cons (build-path src "routes" "keymaps.rkt") (find-files (lambda (q) (regexp-match? #rx"/(multi|undo|blocks|bar|tabs|finder|pins)-keys[.]rkt$" (path->string q))) src)))]) (for/list ([l (in-list (file->lines p))] [i (in-naturals 1)]) (cons (string-append (path->string (find-relative-path src p)) " line " (number->string i)) l))))))
  (define rkts (with-handlers ([void (lambda (e) (list))]) (find-files (lambda (p) (regexp-match? #rx"[.]rkt$" (path->string p))) src)))
  (define names
    (let loop ([t (string-split keys)])
      (cond [(null? t) (list)]
            [(and (equal? (car t) "space") (pair? (cdr t))) (cons (string-append "space " (cadr t)) (loop (cddr t)))]
            [else (cons (car t) (loop (cdr t)))])))
  (define (where k)
    (define rx (regexp (string-append "[(](?:list )?\"" (regexp-quote k) "\" \"([^\"]+)\"[)]")))
    (define hit (for/first ([e (in-list km)] #:when (regexp-match? rx (cdr e))) (cons (car e) (cadr (regexp-match rx (cdr e))))))
    (cond
      [(not hit) (list (string-append "    key " k ": NOT BOUND in routes/keymaps.rkt"))]
      [else
       (define crx (regexp (string-append "[(]hash-set! commands \"" (regexp-quote (cdr hit)) "\"")))
       (define def
         (for/or ([p (in-list rkts)])
           (define ls (with-handlers ([void (lambda (e) (list))]) (file->lines p)))
           (for/first ([l (in-list ls)] [i (in-naturals 1)] #:when (regexp-match? crx l))
             (string-append (substring (path->string p) (string-length src-text)) " line " (number->string i)))))
       (list (string-append "    key " k ": " (car hit) " runs " (cdr hit) ", defined in " (or def "NOWHERE, no hash-set! commands found")))]))
  (append (list (string-append "    screen lines identical to baseline: " (if (equal? ksl bsl) "yes" "no")))
          (apply append (map where names))
          (trace-since (max 0 (- (trace-size) 6000)))))

(define (do-record words)
  (define name (car words))
  (define keys (string-join (cdr words) " "))
  (define tdir (build-path gate-root "tests"))
  (define (found-test n) (let ([f (find-files (lambda (q) (regexp-match? (regexp (string-append "/" n "[.]test$")) (path->string q))) (build-path editor-root "editor"))]) (if (pair? f) (car f) (build-path tdir (string-append n ".test")))))
  (define tpath (found-test name))
  (define old-test (and (file-exists? tpath) (file->string tpath)))
  (define pg (let ([v (line-values (test-lines (found-test "move")) "file")]) (if (pair? v) (car v) "test.aiu")))
  (define base-path "/tmp/aiutd-base.test")
  (define home (find-system-path (quote home-dir)))
  (define (grab n) (with-handlers ([void (lambda (e) "")]) (file->string (build-path home n))))
  (display-to-file (format "test ~a-base\nlevel 2\nfile ~a\nrecord\n~aexpect seconds-under 60\n" name pg "") base-path #:exists (quote truncate))
  (display-to-file (format "test ~a\nlevel 2\nfile ~a\nrecord\nkeys ~a\nexpect seconds-under 30\n" name pg keys) tpath #:exists (quote truncate))
  (run-test base-path)
  (define bs (grab ".aiu-record-screen.txt"))
  (define bf (grab ".aiu-record-file.txt"))
  (define braw (grab ".aiu-record-raw.txt"))
  (run-test tpath)
  (define ks (grab ".aiu-record-screen.txt"))
  (define kf (grab ".aiu-record-file.txt"))
  (define kraw (grab ".aiu-record-raw.txt"))
  (define bsl (record-lines bs))
  (define ksl (record-lines ks))
  (define bfl (record-lines bf))
  (define kfl (record-lines kf))
  (define titletext (with-handlers ([void (lambda (e) "")]) (let ([m (regexp-match #rx"title start\n(.*?)title end" (file->string pg))]) (if m (cadr m) ""))))
  (define expects
    (append (for/list ([l (in-list (first-n (filter (lambda (x) (not (member x bsl))) ksl) 3))]) (string-append "expect screen contains " l))
            (for/list ([l (in-list (first-n (filter (lambda (x) (and (regexp-match? #rx" " x) (not (string-contains? titletext x)) (not (for/or ([k (in-list ksl)]) (string-contains? k x))))) bsl) 3))]) (string-append "expect screen lacks " l))
            (for/list ([l (in-list (first-n (filter (lambda (x) (not (member x bfl))) kfl) 2))]) (string-append "expect file contains " l))
            (for/list ([l (in-list (first-n (filter (lambda (x) (not (for/or ([k (in-list kfl)]) (string-contains? k x)))) bfl) 2))]) (string-append "expect file lacks " l))
            (for/list ([c (in-list (list "grey" "white"))] #:when (and (regexp-match? (colour-rx c) kraw) (not (regexp-match? (colour-rx c) braw)))) (string-append "expect colour " c))))
  (define ok
    (and (pair? expects)
         (begin
           (display-to-file (format "test ~a\nlevel 2\nfile ~a\nkeys ~a\n~a\nexpect seconds-under 30\n" name pg keys (string-join expects "\n")) tpath #:exists (quote truncate))
           (let ([r (run-test tpath)]) (set-box! rec-why (cadddr r)) (caddr r)))))
  (cond
    [ok (display-to-file (format "name ~a\ntest ~a\nkeys ~a\ndoc Recorded from a real run of the keys ~a.\nai gate/tests/~a.test, recorded by aiutd record from the observed screen and file changes.\n" name name keys keys name)
                         (build-path editor-root "editor" "features" (string-append name ".feature")) #:exists (quote truncate))]
    [else (if old-test (display-to-file old-test tpath #:exists (quote truncate)) (when (file-exists? tpath) (delete-file tpath)))])
  (emit (list "AIUTD RECORD" (format "~a  ~a" (if ok "GREEN" "RED") name))
        (if ok expects (append (if (pair? expects) (list) (append (list "nothing changed on screen or in the file, nothing written") (no-change-why keys ksl bsl) (unbox last-evidence))) (unbox rec-why))))
  (when ok (let ([g (find-executable-path "git")] [t (path->string (find-relative-path (simple-form-path editor-root) (simple-form-path tpath)))] [f (string-append "editor/features/" name ".feature")]) (let-values ([(c1 o1) (capture editor-root g (list "add" "--" t f))]) (void)) (let-values ([(c2 o2) (capture editor-root g (list "commit" "-q" "-m" (string-append "test: " name " recorded") "--" t f))]) (void))))
  (if ok 0 1))


(provide rec-why record-lines no-change-why do-record)
