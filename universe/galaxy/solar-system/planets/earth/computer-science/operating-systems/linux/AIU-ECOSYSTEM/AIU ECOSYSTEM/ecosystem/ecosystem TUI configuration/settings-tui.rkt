#lang racket/base
(require racket/file racket/string racket/list racket/port racket/system net/url
         (file "../../../AIU EDITOR/text-editor/editor/tui/theme/theme.rkt"))
(define esc (string (integer->char 27)))
(define cr (string (integer->char 13)))
(define nl (string (integer->char 10)))
(define sp1 (string (integer->char 32)))
(define cfg-file (build-path "AIU NOTATION" "notation" "layouts" "layout-settings.aiu"))
(define rows
  (list
   (list "width" "card width" 120 480 8 "240" "width of a card")
   (list "height" "card height" 40 240 4 "76" "height of a card")
   (list "curve" "arrow curve" 0.05 1 0.05 "0.5" "where arrows bend")
   (list "gap" "gap" 4 100 2 "24" "space between boxes")
   (list "stepx" "step x" 120 600 8 "264" "column distance")
   (list "stepy" "step y" 40 300 4 "100" "row distance")
   (list "margin" "margin" 10 600 10 "200" "free space around")
   (list "pad" "box pad" 4 60 2 "16" "space inside a box")
   (list "head" "box head" 20 140 2 "56" "height of a box title")
   (list "padv" "text pad v" 1 40 1 "10" "card padding top")
   (list "padh" "text pad h" 1 40 1 "12" "card padding side")
   (list "titlesize" "title size" 8 40 1 "15" "card title font")
   (list "descsize" "desc size" 8 30 1 "12" "description font")
   (list "labelsize" "label size" 8 30 1 "13" "box label font")
   (list "scope" "scope" #f #f 0 "demo/" "folder shown, or all")))
(define groups
  (list (cons "cards" (list "width" "height"))
        (cons "arrows" (list "curve"))
        (cons "spacing" (list "gap" "stepx" "stepy" "margin" "pad" "head"))
        (cons "text" (list "padv" "padh" "titlesize" "descsize" "labelsize"))
        (cons "scope" (list "scope"))))
(define vals (make-hash))
(define status "")
(define (row-of k) (assoc k rows))
(define (load!)
  (for ([r rows]) (hash-set! vals (car r) (list-ref r 5)))
  (when (file-exists? cfg-file)
    (for ([l (file->lines cfg-file)])
      (define m (regexp-match #px"^([a-z]+): *(.*)" l))
      (when (and m (assoc (cadr m) rows))
        (hash-set! vals (cadr m) (string-trim (caddr m)))))))
(define (num k) (or (string->number (hash-ref vals k)) 0))
(define (fmt v)
  (define r (/ (round (* v 100)) 100))
  (if (integer? r)
      (number->string (inexact->exact (round r)))
      (number->string (exact->inexact r))))
(define known (map car rows))
(define (save!)
  (define seen (make-hash))
  (define mid
    (for/list ([l (file->lines cfg-file)])
      (define m (regexp-match #px"^([a-z]+): *(.*)" l))
      (cond
        [(and m (member (cadr m) known))
         (hash-set! seen (cadr m) #t)
         (string-append (cadr m) ": " (hash-ref vals (cadr m)))]
        [else l])))
  (define out
    (append*
     (for/list ([l mid])
       (if (string=? l "settings end")
           (append (for/list ([k known] #:unless (hash-ref seen k #f))
                     (string-append k ": " (hash-ref vals k)))
                   (list l))
           (list l)))))
  (display-lines-to-file out cfg-file #:exists (quote truncate)))
(define (reload!)
  (with-handlers ([(lambda (x) #t) (lambda (x) #f)])
    (let ([p (post-pure-port (string->url "http://127.0.0.1:8080/cmd") (string->bytes/utf-8 "reload"))])
      (port->string p)
      (close-input-port p)
      #t)))
(define (push!)
  (save!)
  (thread reload!)
  (set! status "saved"))
(define size-cache (cons 0 (cons 40 80)))
(define (term-size)
  (define now (current-inexact-milliseconds))
  (when (> (- now (car size-cache)) 2000)
    (set! size-cache (cons now (term-size-raw))))
  (cdr size-cache))
(define (term-size-raw)
  (define t (with-output-to-string (lambda () (system "stty size"))))
  (define m (regexp-match #px"([0-9]+) +([0-9]+)" t))
  (if m
      (cons (string->number (cadr m)) (string->number (caddr m)))
      (cons 40 80)))
(define (rep ch n) (make-string (max 0 n) (integer->char ch)))
(define (pad s n)
  (define t (if (> (string-length s) n) (substring s 0 n) s))
  (string-append t (make-string (- n (string-length t)) (integer->char 32))))
(define (bar v lo hi n)
  (define f (max 0 (min 1 (/ (- v lo) (- hi lo)))))
  (define k (inexact->exact (round (* f n))))
  (string-append (rep 9608 k) (rep 9617 (- n k))))
(define (draw sel buf)
  (theme-refresh!)
  (define cols (cdr (term-size)))
  (define w (max 44 (min 78 (- cols 1))))
  (define inner (- w 4))
  (define tx (theme-sgr "text"))
  (define dm (theme-sgr "dim"))
  (define er (theme-sgr "error"))
  (define bold (string-append esc "[1m"))
  (define selk (car (list-ref rows sel)))
  (define out null)
  (define (emit s) (set! out (cons s out)))
  (define (seg col s n) (string-append col (pad s n) theme-reset))
  (emit (string-append bold tx " AIU settings" theme-reset dm "  master view" theme-reset))
  (for ([g groups])
    (define hd (string-append (rep 9472 1) sp1 (car g) sp1))
    (emit (string-append dm (string (integer->char 9581)) hd
                         (rep 9472 (- w 2 (string-length hd)))
                         (string (integer->char 9582)) theme-reset))
    (for ([k (cdr g)])
      (define r (row-of k))
      (define on (string=? k selk))
      (define hot (if on (string-append bold tx) dm))
      (define val (if (and on buf) (string-append buf "_") (hash-ref vals k)))
      (define barc (if (list-ref r 2)
                       (bar (num k) (list-ref r 2) (list-ref r 3) 10)
                       (rep 32 10)))
      (emit (string-append dm (string (integer->char 9474)) sp1
                           (seg hot (string-append (if on (string (integer->char 9656)) sp1) sp1 (list-ref r 1)) 13)
                           (seg hot barc 11)
                           (seg (string-append (if on bold "") tx) val 9)
                           (seg dm (list-ref r 6) (- inner 33))
                           dm sp1 (string (integer->char 9474)) theme-reset)))
    (emit (string-append dm (string (integer->char 9584)) (rep 9472 (- w 2))
                         (string (integer->char 9583)) theme-reset)))
  (emit (string-append dm " h t move  n s change  enter type  e hide" theme-reset))
  (emit (string-append (if (regexp-match? #rx"not running" status) er tx) " " status theme-reset))
  (write-string (string-append esc "[H" (string-join (reverse out) (string-append esc "[K" cr nl)) esc "[K" esc "[J"))
  (flush-output))
(define (move sel d) (modulo (+ sel d) (length rows)))
(define (bump! sel d)
  (define r (list-ref rows sel))
  (define k (car r))
  (if (list-ref r 2)
      (hash-set! vals k (fmt (max (list-ref r 2) (min (list-ref r 3) (+ (num k) (* d (list-ref r 4)))))))
      (hash-set! vals k (if (string=? (hash-ref vals k) "all") (list-ref r 5) "all")))
  (push!))
(define (commit! sel buf)
  (define r (list-ref rows sel))
  (define k (car r))
  (cond
    [(list-ref r 2)
     (let ([n (string->number buf)])
       (if n
           (begin
             (hash-set! vals k (fmt (max (list-ref r 2) (min (list-ref r 3) n))))
             (push!))
           (set! status "not a number")))]
    [(not (string=? buf "")) (hash-set! vals k buf) (push!)]
    [else (set! status "empty, not changed")]))
(define (hide!)
  (write-string (string-append esc "]7704;e" (string (integer->char 7))))
  (flush-output))
(define (run sel buf)
  (draw sel buf)
  (define b (read-byte))
  (cond
    [(eof-object? b) (void)]
    [buf
     (cond
       [(or (= b 10) (= b 13)) (commit! sel buf) (run sel #f)]
       [(or (= b 127) (= b 8))
        (run sel (if (string=? buf "") buf (substring buf 0 (sub1 (string-length buf)))))]
       [(and (>= b 32) (< b 127)) (run sel (string-append buf (string (integer->char b))))]
       [else (run sel buf)])]
    [(= b 27)
     (let* ([b1 (read-byte)] [b2 (read-byte)])
       (cond
         [(eqv? b2 65) (run (move sel -1) #f)]
         [(eqv? b2 66) (run (move sel 1) #f)]
         [(eqv? b2 67) (bump! sel 1) (run sel #f)]
         [(eqv? b2 68) (bump! sel -1) (run sel #f)]
         [else (run sel #f)]))]
    [(= b 3) (void)]
    [(= b 101) (hide!) (run sel #f)]
    [(= b 104) (run (move sel -1) #f)]
    [(= b 116) (run (move sel 1) #f)]
    [(= b 110) (bump! sel -1) (run sel #f)]
    [(= b 115) (bump! sel 1) (run sel #f)]
    [(or (= b 10) (= b 13)) (run sel "")]
    [else (run sel #f)]))
(define (start)
  (system "stty -echo -icanon")
  (write-string (string-append esc "[?1049h" esc "[?25l"))
  (dynamic-wind
   void
   (lambda () (run 0 #f))
   (lambda ()
     (write-string (string-append esc "[?25h" esc "[?1049l"))
     (flush-output)
     (system "stty echo icanon"))))
(module+ main
  (define args (vector->list (current-command-line-arguments)))
  (cond
    [(not (file-exists? cfg-file))
     (displayln "run from the AIU-ECOSYSTEM folder, settings file not found")]
    [(member "check" args)
     (load!)
     (displayln (string-append "ok " (number->string (length rows)) " keys"))]
    [(not (terminal-port? (current-input-port)))
     (displayln "needs a real terminal")]
    [else (load!) (start)]))
