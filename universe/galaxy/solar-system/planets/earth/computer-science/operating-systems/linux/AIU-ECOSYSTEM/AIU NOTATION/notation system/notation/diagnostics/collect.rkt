#lang racket/base
;; One job: gather every finding a reader must be told, in tree order.
;;
;; A finding is data, never a printed line. It carries WHO (the file it is
;; about), WHERE (the 1-based line and the 1-based character column — the
;; pair the text area produces), WHAT (what is wrong, one sentence) and
;; WHAT TO DO (what the reader can do about it). What to do is never empty:
;; an error that cannot say what to do is not an error yet.
;;
;; This file prints nothing and never waits. Reading a tree in memory does
;; not block, so the wait door stays shut and narration/ is not used here:
;; rule 1.1 keeps a block from being silent, not a walk. Every finding is
;; rendered by report.rkt through errors/render.rkt, the only printer of an
;; error in the package — a collector that printed would be a second one.

(require racket/list
         racket/string
         "../errors/raise.rkt"
         "../elements/literals.rkt"
         "../elements/register.rkt"
         "../model/nodes.rkt"
         "../model/outline.rkt"
         "../model/properties.rkt"
         "../filetypes/filetypes.rkt")

(provide collect-findings finding-kinds (struct-out finding))


;; One finding. kind says which check found it; who, line and column say where
;; in the file it is; what and what-to-do say what is wrong and what the
;; reader may do about it. A line of 0 or a column of 0 means the position
;; is not known — never that it is the first one.
(struct finding (kind who line column what what-to-do) #:transparent)

;; The kinds of finding, named here so a caller may count or filter on
;; them without matching words inside a sentence.
(define finding-kinds
  '(unknown-element-name
    tag-names-nothing
    property-no-value
    link-no-target
    parser-recovery
    unknown-file-type
    block-not-in-type
    section-missing
    section-out-of-order
    rule-violated
    question-unverified))

;; link is the keyword a link declaration carries. A link is not a property:
;; a property is a hint for a reader, and a link names a target. The parser
;; does not know the keyword yet — rule B registers tags, language, style,
;; theme, color, format and font — so no page can carry a link today and the
;; link check stays quiet. Registering "link" is the owner's decision (see
;; the README, "Declaration keywords"); this file already reads the
;; shape, so nothing here changes when that decision lands.
(define link-keyword 'link)

;; collect-findings walks an outline and returns every finding in tree order:
;; each recovered parser error and each model problem where it sits. page is
;; the source text the document's offsets index into, or #f when the caller
;; holds only the parse-tree-document; without the page no column can be
;; counted, and every finding's column is 0, which the report prints as
;; "unknown".
(define (collect-findings page o)
  (define who (or (outline-file o) "the document"))
  (define lines (page-lines page))
  (define targets (link-targets who (outline-nodes o)))
  (append (append-map (lambda (n) (walk-node lines who targets n)) (outline-nodes o))
          (type-findings lines who (outline-nodes o))))

;; type-findings checks a page against the file type it declares with kind: on its
;; first block. A page with no kind: is not checked, so every old page stays valid.
(define (type-findings lines who nodes)
  (define top (for/first ([n (in-list nodes)] #:when (block-node? n)) n))
  (define declared (and top (property-of top 'kind)))
  (cond
    [(not declared) '()]
    [else
     (define type-name (string-trim declared))
     (define found (file-type-named type-name))
     (cond
       [(not found)
        (list (finding 'unknown-file-type who (block-node-line top) 0
                       (format "the kind ~a is not a file type; the types are ~a"
                               type-name (type-names))
                       "write one of the types, or add a module for it to filetypes/types/"))]
         [else
          (append
           (if (file-type-allowed-blocks found)
               (append-map (lambda (n) (walk-type lines who found n)) nodes)
               '())
           (section-findings lines who found nodes)
           (contract-findings lines who found nodes))])]))

;; walk-type reports every block under n that the file type does not allow.
(define (walk-type lines who found n)
  (cond
    [(not (block-node? n)) '()]
    [else
     (define allowed (file-type-allowed-blocks found))
     (append
      (if (member (symbol->string (block-node-name n)) allowed)
          '()
          (list (finding 'block-not-in-type who (block-node-line n)
                         (column-at lines (block-node-line n) (block-node-start n))
                         (format "a ~a page may not use a ~a block"
                                 (file-type-name found) (block-node-name n))
                         (format "use one of ~a, or change the kind" allowed))))
      (append-map (lambda (c) (walk-type lines who found c)) (block-node-children n)))]))

;; type-names lists the file types that exist, for a message.
(define (type-names)
  (sort (hash-keys (load-file-types)) string<?))

;; walk-node reads one node and then its children, so a reader meets the
;; findings of a block before the findings of what is inside it.
(define (walk-node lines who targets n)
  (cond
    [(error-node? n) (list (recovered-finding lines who n))]
    [(block-node? n)
     (append (walk-block lines who targets n)
             (append-map (lambda (c) (walk-node lines who targets c))
                         (block-node-children n)))]
    [else
     ;; A node kind this walk does not know is refused, not skipped: a
     ;; finding nobody was told about is worse than a refusal.
     (raise-err 'collect "collect.rkt"
                (format "~a is not a node; the walk reads blocks and error nodes"
                        n))]))

;; walk-block reads one block: first the name the table must know, then every
;; declaration written under its start line, in the order written.
(define (walk-block lines who targets n)
  (define line (block-node-line n))
  (define column (column-at lines line (block-node-start n)))
  (append
   (if (known-name? (block-node-name n))
       '()
       (list (finding 'unknown-element-name who line column
                      (format "the block named ~a is not a registered block name; the table knows ~a"
                              (block-node-name n) (element-names))
                      (format "write one of ~a, or ask for ~a to be registered"
                              (element-names) (block-node-name n)))))
   (append-map (lambda (d) (walk-declaration lines who targets d))
               (block-node-declarations n))))

;; walk-declaration reads one declaration. A declaration reaches this file as
;; the four fields of the document's declaration line, in order — keyword,
;; value, line, byte offset — so a finding can name where
;; the declaration itself is. Any other shape is refused rather than guessed;
;; model/outline.rkt is the file that must fill block-node-declarations with
;; this shape, and it does not yet, so the declaration findings below stay
;; quiet today and fire the day it does.
(define (walk-declaration lines who targets d)
  (unless (and (list? d) (= (length d) 4))
    (raise-err 'collect "collect.rkt"
               "a declaration is not its four fields — keyword, value, line, offset — so this file will not guess which is which"))
  (define keyword (list-ref d 0))
  (define value (list-ref d 1))
  (define line (list-ref d 2))
  (define column (column-at lines line (list-ref d 3)))
  (cond
    [(eq? keyword link-keyword) (walk-link who targets value line column)]
    [(memq keyword property-keywords)
     (walk-property who keyword value line column)]
    [else
     ;; A keyword nobody registered is refused, never read, so that no file
     ;; may invent a property (model/properties.rkt refuses the same way).
     (raise-err 'collect "collect.rkt"
                (format "~a is not a registered declaration keyword; use one of ~a"
                        keyword property-keywords))]))

;; walk-property reads one property declaration. An empty value is a finding
;; of its own: the declaration is there and says nothing, so the reader is
;; told rather than left with a line that looks as if it meant something.
(define (walk-property who keyword value line column)
  (if (string=? (string-trim value) "")
      (list (finding 'property-no-value who line column
                     (format "the ~a declaration has no value" keyword)
                     (format "write a value after the colon, or take the ~a line away"
                             keyword)))
      (if (eq? keyword 'tags)
          (walk-tags who value line column)
          '())))

;; walk-tags reads a tags declaration. A tag names the file it sits in
;;, so the one way a tag can name nothing is to
;; stop being a name at all: a word carrying punctuation cannot be searched
;; for, typed on a phone keyboard or matched later. Resolving a tag against
;; other files is not decided yet and belongs to references/ when it lands.
(define (walk-tags who value line column)
  (append-map
   (lambda (word)
     (if (literal-name? word)
         '()
         (list (finding 'tag-names-nothing who line column
                        (format "the tag ~a is not a name; a tag is letters and dashes"
                                word)
                        "write one tag per word, letters and dashes only"))))
   (parse-tags value)))

;; walk-link reads a link declaration. A link carries one target: the file
;; itself, or a block inside it. A link naming neither is a finding, because
;; a reader who follows it arrives nowhere.
(define (walk-link who targets value line column)
  (define target (string-trim value))
  (if (member target targets)
      '()
      (list (finding 'link-no-target who line column
                     (format "the link names ~a, which is not in this document"
                             (named-target target))
                     (format "point the link at the file or at a block of it; the document holds ~a"
                             targets)))))

;; named-target says an empty target in words, so the sentence above reads the
;; same whether the link names something or nothing.
(define (named-target target)
  (if (string=? target "") "<nothing>" target))

;; link-targets lists what a link may point at: every block name in the tree
;; and the file itself, as the document's file line wrote it. That is what
;; "names something" means inside one document; nothing here reaches outside.
(define (link-targets who nodes)
  (append (block-names nodes) (list who)))

;; block-names walks the tree and lists every block name, as the strings a
;; link target is written with.
(define (block-names nodes)
  (append-map
   (lambda (n)
     (if (block-node? n)
         (cons (symbol->string (block-node-name n))
               (block-names (block-node-children n)))
         '()))
   nodes))

;; recovered-finding is the finding a parser error node becomes. The kind, the
;; what and the what to do are the parser's own words, so the reader is told
;; exactly what was recovered and what to do about it — every stray-text error
;; included, which is what the README registers this file for. The
;; frozen shape says whatToDo is always filled; this file does not invent one
;; when it is not.
(define (recovered-finding lines who n)
  (finding 'parser-recovery who (error-node-line n)
           (column-at lines (error-node-line n) (error-node-offset n))
           (format "the parser recovered from ~a: ~a"
                   (error-node-kind n) (error-node-what n))
           (error-node-what-to-do n)))

;; page-lines splits the page once, so every column is counted against the
;; same lines. With no page there is nothing to count against and every
;; column stays 0.
(define (page-lines page)
  (if page (string-split page "\n" #:trim? #f) #f))

;; column-at is this side of the text area: a byte offset becomes the
;; 1-based character column on a known 1-based line. It answers 0 when there
;; is no page, no such line, or an offset lying before that line — a column is
;; counted or it is unknown, never guessed.
(define (column-at lines line offset)
  (if (or (not lines) (< line 1) (> line (length lines)) (< offset 0))
      0
      (add1 (chars-before-byte (list-ref lines (- line 1))
                               (- offset (bytes-before-line lines line))))))

;; bytes-before-line counts the bytes of every line before the given one, each
;; with its newline, because an offset indexes bytes.
(define (bytes-before-line lines line)
  (let loop ([i 1] [at 0])
    (cond
      [(= i line) at]
      [else (loop (add1 i) (+ at (bytes-of-line (list-ref lines (- i 1)))))])))

;; bytes-of-line counts one line and the newline after it.
(define (bytes-of-line l)
  (+ 1 (bytes-length (string->bytes/utf-8 l))))

;; chars-before-byte counts the characters held by the first n bytes of a
;; line. Offsets are bytes and columns are characters, so the two are counted
;; apart here and nowhere else.
(define (chars-before-byte l n)
  (let loop ([cs (string->list l)] [bytes 0] [chars 0])
    (cond
      [(or (null? cs) (>= bytes n)) chars]
      [else
       (loop (cdr cs)
             (+ bytes (bytes-length (string->bytes/utf-8 (string (car cs)))))
             (add1 chars))])))
;; read-page-text answers the text of the file a document names, or #f when there is no
;; such file. A caller that holds only the document gives no page, so the section titles
;; are read from the file instead.
(define (read-page-text who)
  (cond
    [(and (string? who) (file-exists? who))
     (bytes->string/utf-8
      (call-with-input-file who (lambda (in) (read-bytes (file-size who) in)))
      #\?)]
    [else #f]))

;; declaration-text? answers whether a line of text is a declaration: a registered keyword
;; and a colon at the start of the line.
(define (declaration-text? text)
  (define m (regexp-match #px"^([a-z][a-z-]*):" text))
  (and m (memq (string->symbol (cadr m)) property-keywords) #t))

;; section-title-text reads the text of one title block from the page lines: the lines
;; between its start line and its end line, without declaration lines, joined by spaces.
(define (section-title-text lines t)
  (define start (block-node-line t))
  (define end (block-node-end-line t))
  (define body
    (if (and (>= start 1) (> end start) (<= end (length lines)))
        (take (drop lines start) (- end start 1))
        '()))
  (string-trim
   (string-join
    (filter (lambda (s)
              (not (or (string=? (string-trim s) "")
                       (declaration-text? (string-trim s)))))
            body)
    " ")))

;; page-section-titles lists the titles of the top-level sections of a page, in page order.
(define (page-section-titles lines nodes)
  (for/list ([n (in-list nodes)]
             #:when (and (block-node? n) (eq? (block-node-name n) 'section)))
    (define t
      (for/first ([c (in-list (block-node-children n))]
                  #:when (and (block-node? c) (eq? (block-node-name c) 'title)))
        c))
    (if t (section-title-text lines t) "")))

;; section-findings checks the sections a file type requires. The type lists their titles
;; in order; the page must hold a top-level section with each title, in that order. A
;; missing section is one finding, and a wrong order is one finding. Other sections may
;; follow. When the page text cannot be read, nothing is claimed.
(define (section-findings lines who found nodes)
  (define wanted (required-sections-of (file-type-name found)))
  (define tl (or lines (let ([text (read-page-text who)]) (and text (page-lines text)))))
  (cond
    [(or (null? wanted) (not tl)) '()]
    [else
     (define type (file-type-name found))
     (define top (for/first ([n (in-list nodes)] #:when (block-node? n)) n))
     (define line (if top (block-node-line top) 0))
     (define have (page-section-titles tl nodes))
     (define missing (filter (lambda (t) (not (member t have))) wanted))
     (define present (remove-duplicates (filter (lambda (t) (member t wanted)) have)))
     (define expected (filter (lambda (t) (member t have)) wanted))
     (append
      (for/list ([t (in-list missing)])
        (finding 'section-missing who line 0
                 (format "a ~a page needs a section titled ~a" type t)
                 (format "add a section whose title is ~a; a ~a page holds the sections ~a"
                         t type wanted)))
      (if (equal? present expected)
          '()
          (list (finding 'section-out-of-order who line 0
                         (format "the sections of this ~a page are not in the order the type requires"
                                 type)
                         (format "put the sections in this order: ~a" wanted)))))]))

;; block-raw-lines answers the lines between a block's start line and its end line, leaving out the lines of blocks nested inside it.
(define (block-raw-lines lines n)
  (define start (block-node-line n))
  (define end (block-node-end-line n))
  (define kids
    (for/list ([c (in-list (block-node-children n))] #:when (block-node? c))
      (cons (block-node-line c) (block-node-end-line c))))
  (if (and (>= start 1) (> end start) (<= end (length lines)))
      (for/list ([s (in-list (take (drop lines start) (- end start 1)))]
                 [ln (in-naturals (+ start 1))]
                 #:unless (for/or ([k (in-list kids)]) (and (>= ln (car k)) (<= ln (cdr k)))))
        s)
      '()))

;; block-content-lines answers the raw lines of a block without blank and declaration lines.
(define (block-content-lines lines n)
  (filter (lambda (s)
            (not (or (string=? (string-trim s) "")
                     (declaration-text? (string-trim s)))))
          (block-raw-lines lines n)))

;; block-declared? answers whether a block carries a declaration with the keyword kw.
(define (block-declared? lines n kw)
  (define head
    (takef (block-raw-lines lines n) (lambda (s) (declaration-text? (string-trim s)))))
  (for/or ([s (in-list head)])
    (string-prefix? (string-trim s) (string-append kw ":"))))

;; placed-blocks lists every block that is not a section as (block . title of the section
;; it sits in), in page order; the title is "" for a block outside any section.
(define (placed-blocks lines nodes sec)
  (append-map
   (lambda (n)
     (cond
       [(not (block-node? n)) '()]
       [(eq? (block-node-name n) 'section)
        (define t
          (for/first ([c (in-list (block-node-children n))]
                      #:when (and (block-node? c) (eq? (block-node-name c) 'title)))
            c))
        (placed-blocks lines (block-node-children n) (if t (section-title-text lines t) ""))]
       [else (list (cons n sec))]))
   nodes))

;; contract-applies? answers whether a contract names this block in this section; the
;; section "*" means any section.
(define (contract-applies? c n sec)
  (and (equal? (symbol->string (block-node-name n)) (caddr c))
       (or (equal? (cadr c) "*") (equal? (cadr c) sec))))

;; rule-failure answers a sentence saying how a block breaks a deterministic rule, or #f
;; when the block keeps it.
(define (rule-failure lines n name arg)
  (define ls (block-content-lines lines n))
  (define text (string-join ls " "))
  (define words (length (string-split text)))
  (case name
    [(max-words) (and (> words arg) (format "has ~a words, the most allowed is ~a" words arg))]
    [(min-words) (and (< words arg) (format "has ~a words, the least allowed is ~a" words arg))]
    [(max-lines) (and (> (length ls) arg)
                      (format "has ~a lines, the most allowed is ~a" (length ls) arg))]
    [(must-match) (and (not (regexp-match? (pregexp arg) text))
                       (format "does not match ~a" arg))]
    [(must-not-match) (and (regexp-match? (pregexp arg) text)
                           (format "must not match ~a" arg))]
    [(needs-declaration) (and (not (block-declared? lines n arg))
                              (format "has no ~a: declaration" arg))]
    [else (format "is governed by the unknown rule ~a" name)]))

;; where-text names the place a contract speaks about.
(define (where-text sec)
  (if (equal? sec "") "the page" (format "the section ~a" sec)))

;; check-placed answers the findings of every contract that applies to one block. Rules
;; are checked always. Questions are semantic: the checker cannot answer them, so they
;; are reported as unverified, and only when AIU_QUESTIONS is 1.
(define (check-placed lines who cs ask? n sec)
  (append-map
   (lambda (c)
     (cond
       [(not (contract-applies? c n sec)) '()]
       [(eq? (car c) 'rule)
        (define bad (rule-failure lines n (cadddr c) (list-ref c 4)))
        (if bad
            (list (finding 'rule-violated who (block-node-line n) 0
                           (format "a ~a block in ~a ~a" (caddr c) (where-text sec) bad)
                           (format "change the block so the rule ~a ~a holds; the checker never edits it"
                                   (cadddr c) (list-ref c 4))))
            '())]
       [(and (eq? (car c) 'question) ask?)
        (list (finding 'question-unverified who (block-node-line n) 0
                       (format "a ~a block in ~a must answer: ~a (the checker cannot verify this)"
                               (caddr c) (where-text sec) (cadddr c))
                       "have a person or an AI judge the block against the question"))]
       [else '()]))
   cs))

;; contract-findings checks the contracts of the page's file type against the page. A type
;; without contracts, or a page whose text cannot be read, gives no findings.
(define (contract-findings lines who found nodes)
  (define cs (contracts-of (file-type-name found)))
  (define tl (or lines (let ([text (read-page-text who)]) (and text (page-lines text)))))
  (cond
    [(or (null? cs) (not tl)) '()]
    [else
     (define ask? (equal? (getenv "AIU_QUESTIONS") "1"))
     (append-map (lambda (p) (check-placed tl who cs ask? (car p) (cdr p)))
                 (placed-blocks tl nodes ""))]))
