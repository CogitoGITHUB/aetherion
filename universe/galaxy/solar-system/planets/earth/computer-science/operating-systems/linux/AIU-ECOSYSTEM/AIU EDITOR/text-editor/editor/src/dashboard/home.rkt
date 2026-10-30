#lang racket/base
;; One job: the home screen, what the editor shows when it opens with no file.
;; The screen is an AIU page built in memory and drawn by the notation own
;; view, so it looks like every other page. It opens at once from the last
;; scan kept in the home folder, and scans the pages, the todos and the
;; repositories in the background, so the opening never waits. The scan only
;; reads: no page is written and no repository is changed.

(require racket/file
         racket/list
         racket/path
         racket/port
         racket/string
         racket/system
         "../machine/terminal.rkt")

;; scan is one scan: the root, the pages, the todos and the repositories.
(struct scan (root pages todos repos))

;; skipped are the folder names the scan never goes into.
(define skipped (list "compiled" ".git" "node_modules" "target" "aiu-compiled"))

;; ecosystem-root answers the folder the scan starts from: AIU_ROOT when the
;; launcher gave it, else the folder named AIU-ECOSYSTEM above here.
(define (ecosystem-root)
  (define given (getenv "AIU_ROOT"))
  (if (and given (directory-exists? given))
      (string->path given)
      (let loop ([dir (path->complete-path (current-directory))])
        (define-values (base name dir?) (split-path dir))
        (cond
          [(and (path? name) (string=? (path->string name) "AIU-ECOSYSTEM")) dir]
          [(path? base) (loop base)]
          [else (current-directory)]))))

;; safe-list answers the entries of a folder, or none when it cannot be read.
(define (safe-list dir)
  (with-handlers ([exn:fail? (lambda (why) null)])
    (directory-list dir)))

;; descend? answers whether the scan goes into a folder.
(define (descend? full name)
  (and (directory-exists? full)
       (not (link-exists? full))
       (not (member name skipped))
       (not (char=? (string-ref name 0) #\.))))

;; modified answers when a file was last changed, or 0 when that is unknown.
(define (modified path)
  (with-handlers ([exn:fail? (lambda (why) 0)])
    (file-or-directory-modify-seconds path)))

;; capture runs one program and answers what it printed, and nothing else.
(define (capture exe args)
  (parameterize ([current-error-port (open-output-nowhere)]
                 [current-input-port (open-input-bytes #"")])
    (with-output-to-string
      (lambda () (apply system* exe args)))))

;; short-name answers a page as its folder and its file name.
(define (short-name path)
  (define-values (base name dir?) (split-path path))
  (define parent (and (path? base) (file-name-from-path base)))
  (if parent
      (string-append (path->string parent) "/" (path->string name))
      (path->string name)))

;; find-pages answers the .aiu files under the root, newest first.
(define (find-pages root)
  (define found null)
  (define seen 0)
  (let loop ([dir root])
    (for ([entry (in-list (safe-list dir))])
      (define full (build-path dir entry))
      (define name (path->string entry))
      (cond
        [(> seen 800) (void)]
        [(descend? full name) (loop full)]
        [(and (file-exists? full) (string-suffix? name ".aiu"))
         (set! seen (add1 seen))
         (set! found (cons full found))]
        [else (void)])))
  (sort found > #:key modified))

;; todos-of answers one list per todo line of a page: open or not, the text
;; and the page it is on.
(define (todos-of file)
  (with-handlers ([exn:fail? (lambda (why) null)])
    (if (> (file-size file) 400000)
        null
        (for/list ([line (in-list (call-with-input-file file port->lines))]
                   #:when (regexp-match? #px"^todo:" line))
          (define done? (regexp-match? #px"^todo:\\s+done\\b" line))
          (list (not done?)
                (string-trim (regexp-replace #px"^todo:\\s*(done\\b)?\\s*" line ""))
                (short-name file))))))

;; git-here? answers whether a folder is a repository.
(define (git-here? dir)
  (or (directory-exists? (build-path dir ".git"))
      (file-exists? (build-path dir ".git"))))

;; git-toplevel answers the repository a folder is inside, or nothing.
(define (git-toplevel dir)
  (define git (find-executable-path "git"))
  (and git
       (let ([line (string-trim
                    (capture git (list "-C" (path->string dir) "rev-parse" "--show-toplevel")))])
         (and (not (string=? line ""))
              (directory-exists? line)
              (string->path line)))))

;; find-repos answers the repositories under the root, four folders deep, and
;; the ones the root and the current folder are inside.
(define (find-repos root)
  (define found null)
  (let loop ([dir root] [depth 0])
    (cond
      [(git-here? dir) (set! found (cons dir found))]
      [(< depth 4)
       (for ([entry (in-list (safe-list dir))])
         (define full (build-path dir entry))
         (when (descend? full (path->string entry))
           (loop full (add1 depth))))]
      [else (void)]))
  (remove-duplicates
   (append (reverse found)
           (filter values (list (git-toplevel root) (git-toplevel (current-directory)))))
   #:key path->string))

;; repo-row answers the name, the branch and the changed count of a repository.
;; Untracked files are not counted: walking them is what makes a big
;; repository slow.
(define (repo-row dir)
  (define git (find-executable-path "git"))
  (define out
    (if git
        (capture git (list "-C" (path->string dir) "status" "--porcelain" "-b" "-uno"))
        ""))
  (define lines (string-split out "\n"))
  (define head (if (null? lines) "## ?" (car lines)))
  (define m (regexp-match #px"^## (?:No commits yet on |Initial commit on )?([^. ]+)" head))
  (define last-name (file-name-from-path dir))
  (list (if last-name (path->string last-name) "repo")
        (if m (cadr m) "?")
        (max 0 (sub1 (length lines)))))

;; scan-all is part of the home screen.
(define (scan-all)
  (define root (ecosystem-root))
  (define pages (find-pages root))
  (define repos (find-repos root))
  (scan (path->string root)
        pages
        (append* (map todos-of pages))
        (map repo-row (if (> (length repos) 8) (take repos 8) repos))))

;; The last scan is kept in the home folder, outside the project tree, as plain
;; data: the next opening shows it at once.
(define cache-file
  (build-path (find-system-path (quote home-dir)) ".aiu-home-scan.rktd"))

;; write-cache keeps a scan in the home folder as plain data.
(define (write-cache made)
  (with-handlers ([exn:fail? void])
    (write-to-file (list (scan-root made)
                         (map path->string (scan-pages made))
                         (scan-todos made)
                         (scan-repos made))
                   cache-file
                   #:exists (quote truncate))))

;; read-cache answers the scan kept in the home folder, or nothing.
(define (read-cache)
  (with-handlers ([exn:fail? (lambda (why) #f)])
    (and (file-exists? cache-file)
         (let ([v (file->value cache-file)])
           (and (list? v)
                (= (length v) 4)
                (scan (first v) (map string->path (second v)) (third v) (fourth v)))))))

;; cache holds the scan in memory.
(define cache (box #f))
;; lines-cache holds the last drawing and the width it was drawn at.
(define lines-cache (box #f))
;; running says whether a background scan is going.
(define running (box #f))

;; expecting says that the scan of this opening has not finished yet, so the
;; page says it is scanning from its first paint.
(define expecting (box #t))

;; home-rescan! scans in a thread and answers at once, so the keys stay live.
;; When the scan lands it is kept in memory and in the home folder, and done is
;; called so the screen paints it. A scan already running is not started twice.
(define (home-rescan! done)
  (unless (unbox running)
    (set-box! running #t)
    (thread
     (lambda ()
       (with-handlers ([exn:fail? (lambda (why)
                                    (set-box! running #f)
                                    (set-box! expecting #f)
                                    (done))])
         (let ([made (scan-all)])
           (set-box! cache made)
           (set-box! lines-cache #f)
           (write-cache made)
           (set-box! running #f)
           (set-box! expecting #f)
           (done)))))))

;; scan-age answers how many minutes ago the kept scan was made, or nothing.
(define (scan-age)
  (and (file-exists? cache-file)
       (quotient (- (current-seconds) (file-or-directory-modify-seconds cache-file)) 60)))

;; data answers the scan in memory, or the last one from the home folder, or
;; nothing when no scan has landed yet.
(define (data)
  (or (unbox cache)
      (let ([kept (read-cache)])
        (when kept (set-box! cache kept))
        kept)))

;; home-page answers the path of the nth page of the list, or nothing.
(define (home-page n)
  (define d (data))
  (and d
       (<= 1 n (length (scan-pages d)))
       (path->string (list-ref (scan-pages d) (sub1 n)))))

;; The page is built from blocks, in the notation own words.
(define (title-block title)
  (string-append "title start\nkind: dashboard\ntags: dashboard home pages todos git\n"
                 title "\ntitle end\n"))

;; paragraph-block answers the rows as one paragraph block.
(define (paragraph-block rows)
  (string-append "paragraph start\n" (string-join rows "\n") "\nparagraph end\n"))

;; comment-block puts several blocks under one comment, as the todo pages do.
(define (comment-block note blocks)
  (string-append "comment start\n" note "\n\n" (string-join blocks "\n") "\ncomment end\n"))

;; join-blocks answers the blocks as the text of one page.
(define (join-blocks blocks)
  (string-join blocks "\n"))

;; clip answers a text cut to at most n characters.
(define (clip text n)
  (if (> (string-length text) n)
      (string-append (substring text 0 (max 0 (- n 3))) "...")
      text))

;; page-rows answers the rows of the pages paragraph.
(define (page-rows d n)
  (define pages (scan-pages d))
  (if (null? pages)
      (list "no .aiu page found")
      (append
       (for/list ([p (in-list pages)] [i (in-range n)])
         (format "~a  ~a" (add1 i) (short-name p)))
       (if (> (length pages) n)
           (list (format "... ~a more pages" (- (length pages) n)))
           null))))

;; repo-rows answers one row for each repository.
(define (repo-rows d n)
  (define repos (scan-repos d))
  (if (null? repos)
      (list "git   no repository found")
      (for/list ([r (in-list repos)] [i (in-range n)])
        (format "git   ~a  ~a  ~a" (first r) (second r)
                (if (zero? (third r)) "clean" (format "~a changed" (third r)))))))

;; work-rows answers the todo counts and the repository rows.
(define (work-rows d n)
  (define todos (scan-todos d))
  (define open-count (length (filter car todos)))
  (append
   (list (format "todo  ~a open  ~a done  ~a pages"
                 open-count (- (length todos) open-count) (length (scan-pages d))))
   (repo-rows d n)))

;; todos-block answers the open todos the scan found, each one a paragraph with
;; its todo line, all under one comment. Nothing is made up: when the scan
;; finds none, the block says so.
(define (todos-block d n)
  (define open-todos (filter car (scan-todos d)))
  (cond
    [(null? open-todos)
     (paragraph-block (list "Todos" "no open todo found on any page"))]
    [else
     (comment-block
      "Open todos found on the pages."
      (append
       (for/list ([t (in-list open-todos)] [i (in-range n)])
         (paragraph-block (list (string-append "todo: " (clip (cadr t) 80))
                                (string-append "in " (caddr t)))))
       (if (> (length open-todos) n)
           (list (paragraph-block
                  (list (format "... ~a more open todos" (- (length open-todos) n)))))
           null)))]))

;; home-text answers the page of the home screen: the title, the keys, the
;; pages, the work and the open todos from the last scan, which is shown at
;; once while a new scan runs in the background.
(define (home-text)
  (define d (data))
  (define age (scan-age))
  (define busy? (or (unbox running) (unbox expecting)))
  (join-blocks
   (append
    (list (title-block "AIU DASHBOARD")
          (paragraph-block
           (list "space q quit  ·  space r scan again"
                 "1 to 9 opens that page"
                 (cond
                   [busy? "scanning in the background"]
                   [age (format "last scan ~a min ago" age)]
                   [else "no scan yet"]))))
    (if d
        (list (paragraph-block (cons "Pages" (page-rows d 3)))
              (paragraph-block (cons "Work" (work-rows d 2)))
              (todos-block d 3))
        (list (paragraph-block
               (list "Nothing scanned yet"
                     (if busy?
                         "the page fills in when the scan lands"
                         "press space r to scan the folders"))))))))

;; notation-bin answers the notation binary: the one AIU_NOTATION_BIN names,
;; or the one built under the notation project.
(define (notation-bin)
  (define named (getenv "AIU_NOTATION_BIN"))
  (if (and named (not (string=? named "")))
      (string->path named)
      (build-path (ecosystem-root) "AIU NOTATION" "notation system" "notation"
                  "target" "debug" "notation")))

;; view-text draws a page text with the notation own view and answers the
;; drawing, or nothing when the binary is missing or refuses the page.
(define (view-text text w)
  (with-handlers ([exn:fail? (lambda (why) #f)])
    (let ()
      (define bin (notation-bin))
      (define temp
        (build-path (find-system-path (quote temp-dir))
                    (format "aiu-home-~a.aiu" (current-milliseconds))))
      (cond
        [(not (file-exists? bin)) #f]
        [else
         (dynamic-wind
          void
          (lambda ()
            (display-to-file text temp #:exists (quote truncate))
            (define ok? #f)
            (define out
              (parameterize ([current-error-port (open-output-nowhere)]
                             [current-input-port (open-input-bytes #"")])
                (with-output-to-string
                  (lambda ()
                    (set! ok? (system* bin "view" (path->string temp)
                                       "--width" (number->string w)))))))
            (and ok? (not (string=? (string-trim out) "")) out))
          (lambda ()
            (when (file-exists? temp) (delete-file temp))))]))))

;; home-lines answers the lines of the home screen. It is one screen at every
;; level, so the level keys change nothing here. A drawing that cannot be made
;; shows the page text as it is, so the screen is never blank.
(define (home-lines level panel?)
  (define-values (cols rows) (terminal-size))
  (define w (max 30 (min (- cols 1) 56)))
  (define hit (unbox lines-cache))
  (if (and hit (equal? (car hit) w))
      (cdr hit)
      (let* ([page (home-text)]
             [drawn (view-text page w)]
             [lines (string-split (or drawn page) "\n" #:trim? #f)])
        (set-box! lines-cache (cons w lines))
        lines)))

(provide home-lines
         home-page
         home-rescan!)
