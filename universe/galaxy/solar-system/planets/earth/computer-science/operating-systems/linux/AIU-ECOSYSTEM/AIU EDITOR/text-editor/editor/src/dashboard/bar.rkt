#lang racket/base
;; One job: the bar and the plan of the screen. The bar says the layer, the time,
;; the date, git and the trigger key, and it knows where it stands (bottom, top,
;; left, right or both sides), whether the side strips are docked beside the page
;; or float over it, and how many of its parts show. The tab bar of tabs.rkt
;; stands at the top or the bottom too, and the two can share an edge. Focus mode
;; hides all of it. The live screen asks for one plan per paint. Git is asked in
;; a thread, never in a paint, and the clock is read at each paint, so no timer
;; runs.

(require racket/list
         racket/string
         racket/path
         "../commands/commands.rkt"
         "../routes/keymaps.rkt"
         "box.rkt"
         "tabs.rkt")

;; bar-place holds where the bar stands: bottom, top, left, right, sides or hidden.
(define bar-place (box "bottom"))

;; bar-saved holds the place the bar had before it was hidden.
(define bar-saved (box "bottom"))

;; bar-style holds docked or floating, for the side places.
(define bar-style (box "docked"))

;; bar-count holds how many parts show, from 0 to 5.
(define bar-count (box 5))

;; focus-on holds whether focus mode hides the bar, the tabs and the one line.
(define focus-on (box #f))

;; bar-order are the parts in the order the level adds them.
(define bar-order (list "mode" "time" "save" "date" "keys"))

;; bar-places are the places the place key goes through.
(define bar-places (list "bottom" "top" "left" "right" "sides"))

;; bar-kname answers the name of a key as shown: the space key is SPC.
(define (bar-kname s) (if (string=? s "space") "SPC" s))

;; day-names are the short names of the days, Sunday first.
(define day-names (vector "Sun" "Mon" "Tue" "Wed" "Thu" "Fri" "Sat"))

;; month-names are the short names of the months.
(define month-names (vector "Jan" "Feb" "Mar" "Apr" "May" "Jun" "Jul" "Aug" "Sep" "Oct" "Nov" "Dec"))

;; two answers a number as two digits.
(define (two n) (if (< n 10) (string-append "0" (number->string n)) (number->string n)))

;; clock-time answers the time as 21:30.
(define (clock-time)
  (define d (seconds->date (current-seconds)))
  (string-append (two (date-hour d)) ":" (two (date-minute d))))

;; clock-date answers the day and the date as Fri 30 Oct.
(define (clock-date)
  (define d (seconds->date (current-seconds)))
  (string-append (vector-ref day-names (date-week-day d)) " " (number->string (date-day d)) " "
                 (vector-ref month-names (sub1 (date-month d)))))

;; git-info holds the last git answer.
(define git-info (box #f))

;; git-stamp holds the second git was last asked.
(define git-stamp (box 0))

;; git-busy holds whether a thread is asking git now.
(define git-busy (box #f))

;; git-out answers what one git command prints in a folder, or nothing.
(define (git-out dir args)
  (define git (find-executable-path "git"))
  (if git
      (let-values ([(sp out in err) (apply subprocess #f #f #f git "-C" dir args)])
        (close-output-port in)
        (let ([s (read-string 100000 out)])
          (close-input-port out)
          (close-input-port err)
          (subprocess-wait sp)
          (if (string? s) s "")))
      ""))

;; git-facts answers the git facts as a list: the branch, the changed files, the
;; commits ahead, the commits behind and the last commit. Untracked files are not
;; counted. A folder with no repository answers a text.
(define (git-facts dir)
  (define st (string-split (git-out dir (list "status" "--porcelain" "-b" "-uno")) "\n"))
  (define head (if (null? st) "" (car st)))
  (cond
    [(not (string-prefix? head "## ")) "no repository"]
    [else
     (define m (regexp-match #px"^## (?:No commits yet on |Initial commit on )?([^. ]+)" head))
     (define ahead (regexp-match #px"ahead ([0-9]+)" head))
     (define behind (regexp-match #px"behind ([0-9]+)" head))
     (define stat (git-out dir (list "diff" "--shortstat" "HEAD")))
     (define (stat-n rx) (let ([m (regexp-match rx stat)]) (if m (string->number (cadr m)) 0)))
     (list (if m (cadr m) "?")
           (sub1 (length st))
           (if ahead (string->number (cadr ahead)) 0)
           (if behind (string->number (cadr behind)) 0)
           (string-trim (git-out dir (list "log" "-1" "--format=%h  %s")))
           (length (filter (lambda (l) (and (> (string-length l) 1) (not (memv (string-ref l 0) (list #\space #\?))))) (cdr st)))
           (length (filter (lambda (l) (and (> (string-length l) 1) (not (memv (string-ref l 1) (list #\space #\?))))) (cdr st)))
           (stat-n #px"([0-9]+) insertion")
           (stat-n #px"([0-9]+) deletion"))]))

;; git-text answers the git facts as one row of text.
(define (git-text g)
  (cond
    [(not g) "reading git"]
    [(string? g) g]
    [else
     (string-join
      (filter values
              (list (list-ref g 0)
                    (if (zero? (list-ref g 1)) "clean" (format "~a changed" (list-ref g 1)))
                    (and (> (list-ref g 5) 0) (format "~a staged" (list-ref g 5)))
                    (and (> (list-ref g 6) 0) (format "~a unstaged" (list-ref g 6)))
                    (and (or (> (list-ref g 7) 0) (> (list-ref g 8) 0)) (format "+~a -~a" (list-ref g 7) (list-ref g 8)))
                    (and (> (list-ref g 2) 0) (format "~a ahead" (list-ref g 2)))
                    (and (> (list-ref g 3) 0) (format "~a behind" (list-ref g 3)))
                    (and (not (string=? (list-ref g 4) "")) (list-ref g 4))))
      "  ")]))

;; git-letters answers the git facts as the letters of a side cell: the branch and
;; the changed count.
(define (git-letters g)
  (cond
    [(not g) "git"]
    [(string? g) "none"]
    [else (string-append (list-ref g 0)
                         (if (zero? (list-ref g 1)) "" (format "~~~a" (list-ref g 1))))]))

;; git-refresh-maybe asks git in a thread when the last answer is twenty seconds
;; old, and calls again when the answer changed, so the bar is painted anew.
(define (git-refresh-maybe dir again)
  (when (and (unbox paint-ready) (not (unbox git-busy)) (>= (- (current-seconds) (unbox git-stamp)) 20))
    (set-box! git-busy #t)
    (define first? (zero? (unbox git-stamp)))
    (set-box! git-stamp (current-seconds))
    (thread
     (lambda ()
       (void)
       (define row (with-handlers ([(lambda (e) #t) (lambda (e) "git unavailable")])
                     (git-facts dir)))
       (define changed? (not (equal? row (unbox git-info))))
       (set-box! git-info row)
       (set-box! tab-git-text (git-text row))
       (set-box! git-busy #f)
       (when changed? (again))))))

;; bar-rows answers the rows of the bar as a box of the full width: the layer and
;; the file on the top edge with the time and the date, the trigger row, and the
;; git row. A part that is not in names is left out.
(define (bar-rows layer short pending g width names)
  (define (has? n) (member n names))
  (define trig (let ([t (assoc layer trigger-of)]) (if t (cdr t) "-")))
  (define waiting
    (if (pair? pending) (format "  waiting after ~a" (string-join (map bar-kname pending) " ")) ""))
  (define title (if (has? "mode") (format "~a [~a] · ~a" (mode-label layer) (unbox kind-filter) short) "bar"))
  (define stamp
    (string-join (filter values (list (and (has? "time") (clock-time)) (and (has? "date") (clock-date)))) "  "))
  (define middle
    (append (if (has? "keys")
                (list (body-line (format "trigger ~a~a" (bar-kname trig) waiting) width))
                null)
            (if (and (has? "save") (unbox unsaved))
                (list (edge-line "├" "┤" "save" "" width) (body-line "unsaved  SPC s saves" width))
                null)))
  (if (null? names)
      null
      (append (list (edge-line "╭" "╮" title stamp width)) middle (list (rule-line "╰" "╯" width)))))

;; cell-chars answers the text of one part of a side strip, to be drawn one
;; letter to a row.
(define (cell-chars name layer g)
  (cond
    [(string=? name "mode") (format "~a ~a" (mode-label layer) (unbox kind-filter))]
    [(string=? name "time") (clock-time)]
    [(string=? name "date") (clock-date)]
    [(string=? name "save") "SAVE"]
    [else (let ([t (assoc layer trigger-of)]) (bar-kname (if t (cdr t) "-")))]))

;; strip-lines answers the rows of a side strip, five columns wide: one cell for
;; each part, the letters upright, a line between the cells. A docked strip runs
;; the full height it is given, a floating one is as tall as its cells.
(define (strip-lines names layer g height docked?)
  (cond
    [(null? names) null]
    [else
     (define n (length names))
     (define budget (max 1 (quotient (- height 2 (sub1 n)) n)))
     (define body
       (append*
        (for/list ([nm (in-list names)] [i (in-naturals)])
          (define chars (string->list (cell-chars nm layer g)))
          (define shown (if (> (length chars) budget) (take chars budget) chars))
          (append (if (zero? i) null (list "├───┤"))
                  (for/list ([c (in-list shown)]) (string-append "│ " (string c) " │"))))))
     (define filler
       (if docked?
           (for/list ([i (in-range (max 0 (- height 2 (length body))))]) "│   │")
           null))
     (append (list "╭───╮") body filler (list "╰───╯"))]))

;; bar-plan is what one paint needs: the columns taken on the left and the right,
;; the rows taken at the top and the bottom, the text of the bottom rows, the
;; escape text drawn over the page, and whether the old one line mode line is used.
(struct bar-plan (left right top bottom text overlay line?) #:transparent)

;; bar-plan-of answers the plan for one paint. The width and the height are those
;; of the whole screen. The home screen and a screen under 14 rows keep the old
;; one line mode line; the tabs need 16 rows. Focus mode takes everything away.
;; The tabs and the bar can stand at the same edge, apart or sharing one line.
(define (bar-plan-of session pending width height home? again)
  (define layer (the-layer session))
  (define file (session-file session))
  (define short (let ([n (file-name-from-path file)]) (if n (path->string n) (path->string file))))
  (define dir (path->string (or (path-only (path->complete-path file)) (current-directory))))
  (define want (if home? "line" (unbox bar-place)))
  (define place (if (and (member want (list "bottom" "top")) (< height 14)) "line" want))
  (define names (take bar-order (min (length bar-order) (max 0 (unbox bar-count)))))
  (define tabs-on?
    (and (not home?) (>= height 16) (not (string=? (unbox tab-place) "hidden"))))
  (cond
    [(unbox focus-on) (bar-plan 0 0 0 0 "" "" #f)]
    [else
     (unless (or (unbox unsaved) (member place (list "line" "hidden"))) (git-refresh-maybe dir again))
     (define g (unbox git-info))
     (define undo-lines (if (string=? layer "undo") ((unbox undo-rows-hook) width height) null))
     (define bar-lines
       (if (member place (list "bottom" "top")) (bar-rows layer short pending g width names) null))
     (define tab-lines
       (if tabs-on? (tab-rows (path->string (path->complete-path file)) width again) null))
     (define (group where)
       (define t (if (and tabs-on? (string=? (unbox tab-place) where)) tab-lines null))
       (define b (if (string=? place where) bar-lines null))
       (cond [(and (pair? t) (pair? b) (unbox tab-joined))
              (append (drop-right t 1) (list (join-edge (car b))) (cdr b))]
             [else (append t b)]))
     (define top-lines (group "top"))
     (define bottom-lines (if (pair? undo-lines) undo-lines (group "bottom")))
     (define top-n (length top-lines))
     (define sh (max 3 (- height top-n (length bottom-lines))))
     (define left-names
       (cond [(string=? place "left") names]
             [(string=? place "sides") (filter (lambda (n) (or (member n (list "mode" "keys")) (and (string=? n "save") (unbox unsaved)))) names)]
             [else null]))
     (define right-names
       (cond [(string=? place "right") names]
             [(string=? place "sides") (filter (lambda (n) (member n (list "time" "date"))) names)]
             [else null]))
     (define docked?
       (and (string=? (unbox bar-style) "docked")
            (>= (- width (if (null? left-names) 0 5) (if (null? right-names) 0 5)) 20)))
     (define lines-l (strip-lines left-names layer g sh docked?))
     (define lines-r (strip-lines right-names layer g sh docked?))
     (define drawn
       (string-append (draw-at top-lines 1 1)
                      (if (null? lines-l) "" (draw-at lines-l (+ top-n 1) 1))
                      (if (null? lines-r) "" (draw-at lines-r (+ top-n 1) (max 1 (- width 4))))))
     (define line? (and (string=? place "line") (null? undo-lines)))
     (bar-plan (if (and docked? (pair? lines-l)) 5 0)
               (if (and docked? (pair? lines-r)) 5 0)
               top-n
               (if line? 1 (length bottom-lines))
               (string-join bottom-lines "\n")
               (if (string=? drawn "") "" (white drawn))
               line?)]))

;; put-place! stands the bar at a place and keeps the place for the hide key.
(define (put-place! p)
  (set-box! bar-place p)
  (set-box! bar-saved p))

;; command-bar-mode enters the bar layer.
(define (command-bar-mode session words)
  (set-layer! session "bar")
  (cons #t "layer: bar"))

;; command-bar-level-mode enters the level adjuster.
(define (command-bar-level-mode session words)
  (set-layer! session "bar-level")
  (cons #t "layer: bar-level"))

;; command-bar-place-next moves the bar to the next place and goes round. A
;; hidden bar comes back first.
(define (command-bar-place-next session words)
  (define now (if (string=? (unbox bar-place) "hidden") (unbox bar-saved) (unbox bar-place)))
  (define tail-of (member now bar-places))
  (define next (if (and tail-of (pair? (cdr tail-of))) (cadr tail-of) (car bar-places)))
  (put-place! next)
  (cons #t (format "bar: ~a" next)))

;; command-bar-bottom stands the bar at the bottom.
(define (command-bar-bottom session words) (put-place! "bottom") (cons #t "bar: bottom"))

;; command-bar-top stands the bar at the top.
(define (command-bar-top session words) (put-place! "top") (cons #t "bar: top"))

;; command-bar-left stands the bar on the left.
(define (command-bar-left session words) (put-place! "left") (cons #t "bar: left"))

;; command-bar-right stands the bar on the right.
(define (command-bar-right session words) (put-place! "right") (cons #t "bar: right"))

;; command-bar-sides stands the bar on both sides.
(define (command-bar-sides session words) (put-place! "sides") (cons #t "bar: sides"))

;; command-bar-style switches the side strips between docked and floating.
(define (command-bar-style session words)
  (set-box! bar-style (if (string=? (unbox bar-style) "docked") "floating" "docked"))
  (cons #t (format "bar: ~a" (unbox bar-style))))

;; command-bar-hide hides the bar, or shows it again where it stood.
(define (command-bar-hide session words)
  (cond [(string=? (unbox bar-place) "hidden") (set-box! bar-place (unbox bar-saved))]
        [else (set-box! bar-saved (unbox bar-place))
              (set-box! bar-place "hidden")])
  (cons #t (format "bar: ~a" (unbox bar-place))))

;; command-bar-less hides one part of the bar.
(define (command-bar-less session words)
  (set-box! bar-count (max 0 (sub1 (unbox bar-count))))
  (cons #t (format "bar level: ~a" (unbox bar-count))))

;; command-bar-more shows one more part of the bar.
(define (command-bar-more session words)
  (set-box! bar-count (min (length bar-order) (add1 (unbox bar-count))))
  (cons #t (format "bar level: ~a" (unbox bar-count))))

;; command-focus-toggle turns focus mode on or off: on, the bar, the tabs and the
;; one line mode line are all hidden and the page has the whole screen.
(define (command-focus-toggle session words)
  (set-box! focus-on (not (unbox focus-on)))
  (cons #t (if (unbox focus-on) "focus: on" "focus: off")))

;; The commands are added to the command table when this module is loaded, so the
;; keys find them and the gate sees the same table the editor does.
(hash-set! commands "bar-mode" command-bar-mode)
(hash-set! commands "bar-level-mode" command-bar-level-mode)
(hash-set! commands "bar-place-next" command-bar-place-next)
(hash-set! commands "bar-bottom" command-bar-bottom)
(hash-set! commands "bar-top" command-bar-top)
(hash-set! commands "bar-left" command-bar-left)
(hash-set! commands "bar-right" command-bar-right)
(hash-set! commands "bar-sides" command-bar-sides)
(hash-set! commands "bar-style" command-bar-style)
(hash-set! commands "bar-hide" command-bar-hide)
(hash-set! commands "bar-less" command-bar-less)
(hash-set! commands "bar-more" command-bar-more)
(hash-set! commands "focus-toggle" command-focus-toggle)

;; The bar, for the live screen above it.
;; git-stale! makes the git row ask again at the next paint.
(define (git-stale!) (set-box! git-stamp 1))

(provide git-stale! (struct-out bar-plan)
         bar-plan-of)

;; undo-table holds the real commands of the undo layer; undo.rkt fills it when it is loaded.
(define undo-table (make-hash))

;; undo-rows-hook answers the rows of the undo panel for a width and a height; undo.rkt sets it.
(define undo-rows-hook (box (lambda (width height) null)))

;; undo-path is the undo module beside this file, or false.
(define undo-path
  (let ([src (variable-reference->module-source (#%variable-reference))])
    (and (path? src)
         (let-values ([(base name dir?) (split-path src)])
           (and (path? base) (simplify-path (build-path base "undo.rkt")))))))

;; undo-stub makes a command that loads the undo module on first use and then runs the real command.
(define (undo-stub name)
  (lambda (session words)
    (with-handlers ([void (lambda (e) (cons #t (format "undo failed: ~a" (if (exn? e) (exn-message e) e))))])
      (when undo-path (dynamic-require undo-path #f))
      (let ([f (hash-ref undo-table name #f)])
        (if f (f session words) (cons #t "undo is not available"))))))

;; The undo commands enter the command table as stubs, so the keys and the gate see them at once.
(for ([name (in-list (list "undo-mode" "undo-back" "undo-forward" "undo-up" "undo-down"
                           "undo-branch-back" "undo-branch-forward" "undo-tip" "undo-mark"
                           "undo-unmark" "undo-diff" "undo-live" "undo-keep" "undo-cancel"))])
  (hash-set! commands name (undo-stub name)))

(provide undo-table undo-rows-hook)
