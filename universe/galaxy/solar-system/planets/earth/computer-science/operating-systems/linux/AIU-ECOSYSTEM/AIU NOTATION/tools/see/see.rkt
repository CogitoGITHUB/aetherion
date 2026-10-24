#lang racket/base
;; see.rkt -- show a .aiu file in the terminal as a formatted page.
;; Why: the file keeps its start and end lines so any tool can read it, but a
;; reader wants the page: file title, numbered sections, wrapped text, framed
;; code, and none of the marks.
;; Called by: the Nushell command "see" (tools/see/INDEX.org).
;; Usage: racket see.rkt FILE [--plain] [--width N]
;; This is a viewer, not the checker: it shows what it can and lists problems
;; at the end. The real check is: aiu check FILE
(require racket/string racket/file)

;; ---------- command line ----------

;; no color codes when true
(define plain? #f)
;; terminal width given by the caller
(define width 80)
;; the file to show
(define target #f)

;; read the arguments: FILE, --plain, --width N
(let loop ([as (vector->list (current-command-line-arguments))])
  (cond
    [(null? as) (void)]
    [(equal? (car as) "--plain")
     (set! plain? #t)
     (loop (cdr as))]
    [(and (equal? (car as) "--width") (pair? (cdr as)))
     (let ([n (string->number (cadr as))])
       (when (and n (exact-integer? n) (> n 20))
         (set! width n)))
     (loop (cddr as))]
    [else
     (set! target (car as))
     (loop (cdr as))]))

(unless target
  (eprintf "usage: see FILE [--plain] [--width N]\n")
  (exit 2))
(unless (file-exists? target)
  (eprintf "see: no such file: ~a\n" target)
  (exit 2))

;; number of text columns used for wrapping
(define cols (max 30 (min (- width 2) 100)))

;; ---------- colors ----------

;; the escape character that starts a color code
(define esc (string (integer->char 27)))

;; wrap s in the style codes (a list of numbers); unchanged in plain mode
(define (sgr codes s)
  (if (or plain? (null? codes) (equal? s ""))
      s
      (string-append esc "[" (string-join (map number->string codes) ";") "m" s esc "[0m")))

;; color names a block may ask for with a "color:" line
(define color-table
  '(("red" . 31) ("green" . 32) ("yellow" . 33) ("blue" . 34)
    ("magenta" . 35) ("cyan" . 36) ("white" . 37) ("gray" . 90) ("grey" . 90)))

;; ---------- output ----------

;; true when the last thing printed was a blank line (or nothing yet)
(define last-blank? #t)

;; print one line
(define (out s)
  (display s)
  (newline)
  (set! last-blank? #f))

;; print a blank line unless one was just printed
(define (gap!)
  (unless last-blank?
    (newline)
    (set! last-blank? #t)))

;; ---------- problems found while reading ----------

;; messages collected, newest first
(define problems '())

;; remember a problem on a line
(define (problem! n msg)
  (set! problems (cons (format "line ~a: ~a" n msg) problems)))

;; ---------- reading the file into blocks ----------

;; one block: name, start line, declarations, body lines, child blocks
;; (declarations, lines and kids are kept newest first while reading)
(struct blk (name line decls lines kids) #:mutable)

;; a line that opens or closes a block: "<name> start" or "<name> end"
(define mark-rx #px"^([a-z][a-z0-9-]*) (start|end)[ \t]*$")

;; a declaration line directly under a start line: "keyword: value"
(define decl-rx
  #px"^(tags|language|style|theme|color|format|font|level|kind|status):[ \t]*(.*?)[ \t]*$")

;; blocks whose body is opaque: nothing inside them opens or closes a block
(define opaque-names '("code" "comment"))

;; the whole file is one block called root
(define root (blk "root" 0 '() '() '()))

;; the open blocks, innermost first
(define stack (list root))

;; true right after a start line, while declaration lines are still allowed
(define decls-open? #f)

;; true for blocks that hold other blocks instead of text
(define (container? b)
  (and (member (blk-name b) '("root" "section")) #t))

;; take one non-mark line as a declaration, body text, or stray text
(define (consume-content! top ln i)
  (define dm
    (and decls-open?
         (not (equal? (blk-name top) "root"))
         (regexp-match decl-rx ln)))
  (cond
    [dm
     (set-blk-decls! top (cons (cons (cadr dm) (caddr dm)) (blk-decls top)))]
    [else
     (set! decls-open? #f)
     (cond
       [(container? top)
        (unless (equal? (string-trim ln) "")
          (problem! i "text outside any block")
          (set-blk-kids! top (cons (blk "stray" i '() (list ln) '()) (blk-kids top))))]
       [else
        (set-blk-lines! top (cons ln (blk-lines top)))])]))

;; pop the stack down to and including the nearest block called name;
;; returns how many blocks were left open inside it
(define (pop-to! name)
  (let loop ([s stack] [n 0])
    (cond
      [(equal? (blk-name (car s)) name)
       (set! stack (cdr s))
       n]
      [else (loop (cdr s) (add1 n))])))

;; handle "<name> end"
(define (close-block! name i)
  (set! decls-open? #f)
  (cond
    [(equal? name "root")
     (problem! i "'root end' is not a block")]
    [(equal? (blk-name (car stack)) name)
     (set! stack (cdr stack))]
    [(member name (map blk-name stack))
     (let ([n (pop-to! name)])
       (problem! i (format "'~a end' also closed ~a block(s) left open inside it" name n)))]
    [else
     (problem! i (format "'~a end' has no matching '~a start'" name name))]))

;; handle one line of the file
(define (parse-line! ln i)
  (define top (car stack))
  (define m (regexp-match mark-rx ln))
  (define opaque? (and (member (blk-name top) opaque-names) #t))
  (cond
    ;; inside code or comment only the matching end line is special
    [(and opaque?
          (not (and m (equal? (cadr m) (blk-name top)) (equal? (caddr m) "end"))))
     (consume-content! top ln i)]
    ;; "<name> start" opens a block inside the current one
    [(and m (equal? (caddr m) "start"))
     (let ([b (blk (cadr m) i '() '() '())])
       (set-blk-kids! top (cons b (blk-kids top)))
       (set! stack (cons b stack))
       (set! decls-open? #t))]
    ;; "<name> end" closes a block
    [(and m (equal? (caddr m) "end"))
     (close-block! (cadr m) i)]
    ;; anything else is content
    [else (consume-content! top ln i)]))

;; ---------- reading a block's parts ----------

;; the children of a block, in file order
(define (kids b) (reverse (blk-kids b)))

;; the body lines of a block, in file order
(define (body-lines b) (reverse (blk-lines b)))

;; the value of a declaration such as "style" on a block, or #f
(define (decl b key)
  (let ([p (assoc key (blk-decls b))])
    (and p (cdr p))))

;; a block's body as one line of text (used for titles)
(define (block-text b)
  (string-join
   (map string-trim
        (filter (lambda (s) (not (equal? (string-trim s) ""))) (body-lines b)))
   " "))

;; style codes asked for by "style:" and "color:" lines
(define (style-codes b)
  (define toks (string-split (or (decl b "style") "")))
  (define from-style
    (apply append
           (for/list ([t (in-list toks)])
             (cond
               [(equal? t "bold") '(1)]
               [(equal? t "dim") '(2)]
               [(equal? t "italic") '(3)]
               [(equal? t "underline") '(4)]
               [else '()]))))
  (define c (decl b "color"))
  (define from-color
    (let ([p (and c (assoc (string-downcase c) color-table))])
      (if p (list (cdr p)) '())))
  (append from-style from-color))

;; the first title block among some blocks, or #f
(define (find-title ks)
  (cond
    [(null? ks) #f]
    [(equal? (blk-name (car ks)) "title") (car ks)]
    [else (find-title (cdr ks))]))

;; ---------- text layout ----------

;; break text into lines no longer than w characters
(define (wrap-words text w)
  (let loop ([ws (string-split text)] [cur ""] [acc '()])
    (cond
      [(null? ws) (reverse (if (equal? cur "") acc (cons cur acc)))]
      [(equal? cur "") (loop (cdr ws) (car ws) acc)]
      [(<= (+ (string-length cur) 1 (string-length (car ws))) w)
       (loop (cdr ws) (string-append cur " " (car ws)) acc)]
      [else (loop ws "" (cons cur acc))])))

;; join body lines into groups; a blank line starts a new group
(define (paragraph-groups lines)
  (let loop ([ls lines] [cur '()] [acc '()])
    (cond
      [(null? ls)
       (reverse (if (null? cur) acc (cons (string-join (reverse cur) " ") acc)))]
      [(equal? (string-trim (car ls)) "")
       (loop (cdr ls) '()
             (if (null? cur) acc (cons (string-join (reverse cur) " ") acc)))]
      [else (loop (cdr ls) (cons (string-trim (car ls)) cur) acc)])))

;; remove blank lines from the front of a list of lines
(define (drop-blank ls)
  (cond
    [(and (pair? ls) (equal? (string-trim (car ls)) "")) (drop-blank (cdr ls))]
    [else ls]))

;; ---------- printing blocks ----------

;; numbering counters, one per section depth
(define counters (make-vector 12 0))

;; count one more section at this depth; returns the label such as "1.2.3"
(define (heading-number! depth)
  (vector-set! counters depth (add1 (vector-ref counters depth)))
  (for ([d (in-range (add1 depth) 12)])
    (vector-set! counters d 0))
  (string-join
   (for/list ([d (in-range 1 (add1 depth))])
     (number->string (vector-ref counters d)))
   "."))

;; the number of comment blocks left out of the page
(define hidden-comments 0)

;; true once the first top-level title has been shown as the file title
(define seen-file-title? #f)

;; print the file title: big, underlined, tags below
(define (print-file-title b)
  (define text (block-text b))
  (gap!)
  (for ([l (in-list (wrap-words text cols))])
    (out (sgr (append '(1 33) (style-codes b)) l)))
  (out (sgr '(2) (make-string (min cols (max 3 (string-length text))) #\═)))
  (let ([t (decl b "tags")])
    (when (and t (not (equal? t "")))
      (out (sgr '(2) (string-append "tags: " t)))))
  (gap!))

;; print a numbered section heading
(define (print-heading depth label text b)
  (define base
    (case (min depth 3)
      [(1) '(1 36)]
      [(2) '(1 34)]
      [else '(1)]))
  (define line (string-append label "  " text))
  (gap!)
  (for ([l (in-list (wrap-words line cols))])
    (out (sgr (append base (style-codes b)) l)))
  (when (= depth 1)
    (out (sgr '(2) (make-string (min cols (max 3 (string-length line))) #\─))))
  (gap!))

;; print an older flat heading block: bold, no number
(define (print-legacy-heading b)
  (define lv
    (let ([n (string->number (or (decl b "level") "1"))])
      (if (and n (exact-integer? n) (>= n 1)) n 1)))
  (gap!)
  (out (sgr (append (if (= lv 1) '(1 36) '(1)) (style-codes b)) (block-text b)))
  (gap!))

;; print a paragraph block, wrapped to the terminal width
(define (print-text b)
  (define codes (style-codes b))
  (for ([g (in-list (paragraph-groups (body-lines b)))]
        [k (in-naturals)])
    (when (> k 0) (gap!))
    (for ([l (in-list (wrap-words g cols))])
      (out (sgr codes l)))))

;; print a code block in a frame, exactly as written
(define (print-code b)
  (define lang (or (decl b "language") ""))
  (define label (if (equal? lang "") "code" lang))
  (define body (reverse (drop-blank (reverse (drop-blank (body-lines b))))))
  (out (sgr '(2) (string-append "┌─ " label)))
  (for ([l (in-list body)])
    (out (string-append (sgr '(2) "│ ") (sgr '(32) l))))
  (out (sgr '(2) "└─")))

;; print one block (and what it holds) at a section depth
(define (render! b depth)
  (define name (blk-name b))
  (cond
    [(equal? name "section")
     (let* ([d (min (add1 depth) 11)]
            [label (heading-number! d)]
            [ks (kids b)]
            [t (find-title ks)])
       (cond
         [t
          (print-heading d label (block-text t) t)
          (unless (eq? t (car ks))
            (problem! (blk-line t) "a section's title must be its first block"))]
         [else
          (print-heading d label "(untitled section)" b)
          (problem! (blk-line b) "section has no title block")])
       (for ([k (in-list ks)])
         (unless (eq? k t)
           (render! k d))))]
    [(equal? name "title")
     (cond
       [(and (= depth 0) (not seen-file-title?))
        (set! seen-file-title? #t)
        (print-file-title b)]
       [else
        (gap!)
        (out (sgr (append '(1) (style-codes b)) (block-text b)))
        (gap!)])]
    [(equal? name "paragraph")
     (gap!)
     (print-text b)]
    [(equal? name "code")
     (gap!)
     (print-code b)]
    [(equal? name "comment")
     (set! hidden-comments (add1 hidden-comments))]
    [(equal? name "heading")
     (print-legacy-heading b)]
    [(equal? name "stray")
     (gap!)
     (out (sgr '(1 31)
               (string-append "! stray text (outside any block): "
                              (string-trim (car (blk-lines b))))))]
    [else
     (gap!)
     (out (sgr '(2 33) (string-append "? unknown block: " name)))
     (print-text b)])
  ;; blocks that hold text may still hold blocks, such as a comment
  (unless (equal? name "section")
    (for ([k (in-list (kids b))])
      (render! k depth))))

;; ---------- run ----------

;; read every line of the file
(for ([ln (in-list (file->lines target))]
      [i (in-naturals 1)])
  (parse-line! ln i))

;; blocks still open at the end of the file are problems
(for ([b (in-list stack)])
  (unless (equal? (blk-name b) "root")
    (problem! (blk-line b) (format "'~a start' is never closed" (blk-name b)))))

;; the file must have a title block at the top level
(unless (find-title (kids root))
  (problem! 1 "the file has no title block"))

;; print the page
(for ([k (in-list (kids root))])
  (render! k 0))

;; footer: hidden comments, then problems
(when (> hidden-comments 0)
  (gap!)
  (out (sgr '(2) (format "(~a comment block~a hidden)"
                         hidden-comments
                         (if (= hidden-comments 1) "" "s")))))
(unless (null? problems)
  (gap!)
  (out (sgr '(1 31) (format "~a problem~a found:"
                            (length problems)
                            (if (= (length problems) 1) "" "s"))))
  (for ([p (in-list (reverse problems))])
    (out (sgr '(31) (string-append "  " p))))
  (out (sgr '(2) "run: aiu check FILE   for the full check")))

;; exit code: 0 when clean, 1 when problems were listed
(exit (if (null? problems) 0 1))
