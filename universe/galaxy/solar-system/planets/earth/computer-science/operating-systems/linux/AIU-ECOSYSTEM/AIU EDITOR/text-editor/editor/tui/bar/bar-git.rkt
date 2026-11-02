#lang racket/base
;; One job: the git facts of the bar. Git is asked in a thread every twenty seconds, never in a paint.
(require racket/list racket/string
         "../float/box.rkt"
         "../tabs/tabs.rkt")

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

;; git-stale! makes the git row ask again at the next paint.
(define (git-stale!) (set-box! git-stamp 1))

(provide git-info git-stamp git-busy git-out git-facts git-text git-letters git-refresh-maybe git-stale!)
