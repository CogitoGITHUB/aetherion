#lang racket/base
;; One job: the gate of the aiutd tool - the stage lists of each level, reading the gate output and running the stages.

(require racket/system racket/string racket/list racket/file racket/path "update-table.rkt" "update-screen.rkt" "update-evidence.rkt" "update-drive.rkt")

(provide gate-run parse-stages parse-times stage-label stage-args level-1-stages level-2-stages)

;; parse-times reads the TIME lines of the gate and answers a list of (stage seconds).
(define (parse-times text)
  (for/list ([l (in-list (string-split text "\n"))]
             #:when (regexp-match? #px"^TIME \\S+ [0-9]+$" (string-trim l)))
    (define p (string-split (string-trim l)))
    (list (cadr p) (/ (round (/ (string->number (caddr p)) 100.0)) 10.0))))

;; level-1-stages are the quick gate stages, about 20 s together.
(define level-1-stages "naming,one-way,language-split,comment-lint,notation-check,dashboard-check,secret-check,git-check")

;; level-2-stages add the medium stages, about 60 s more.
(define level-2-stages (string-append level-1-stages ",paren-check,plugin-check,send-check,route-check,explorer-check,security-gate"))

;; stage-args answers the arguments that pick the gate stages of a level; level 3 runs all.
(define (stage-args level)
  (cond [(= level 1) (list "--only" level-1-stages)] [(= level 2) (list "--only" level-2-stages)] [else (list)]))

;; stage-label names the stage set of a level for the report.
(define (stage-label level)
  (cond [(= level 1) "quick stages"] [(= level 2) "quick and medium stages"] [else "all 17 stages"]))

;; parse-stages reads the gate output and answers one list per stage: name, seconds, exit code, output lines.
(define (parse-stages text)
  (define tail-rx #px"^(stages that checked nothing|NOTHING-TO-CHECK above|light gate:)")
  (define blocks
    (let loop ([ls (string-split text "\n")] [cur #f] [acc (list)])
      (cond
        [(null? ls) (reverse (if cur (cons (reverse cur) acc) acc))]
        [(regexp-match? #rx"^--- " (car ls))
         (loop (cdr ls) (list (car ls)) (if cur (cons (reverse cur) acc) acc))]
        [cur (loop (cdr ls) (cons (car ls) cur) acc)]
        [else (loop (cdr ls) cur acc)])))
  (for/list ([b (in-list blocks)])
    (define (field tag)
      (for/or ([l (in-list (cdr b))])
        (define m (regexp-match (pregexp (string-append "^" tag " [^ ]+ ([0-9]+)$")) (string-trim l)))
        (and m (string->number (cadr m)))))
    (define ms (or (field "TIME") 0))
    (define code (or (field "CODE") 1))
    (define body
      (filter (lambda (l)
                (and (not (string=? (string-trim l) ""))
                     (not (regexp-match? #px"^(TIME|CODE) " (string-trim l)))
                     (not (regexp-match? tail-rx l))))
              (cdr b)))
    (list (substring (car b) 4) (/ (round (/ ms 100.0)) 10.0) code body)))

;; gate-run runs the gate with one nu call per stage for levels 1 and 2, a live line before and after each, and answers code and output.
(define (gate-run nu level)
  (define stages (cond [(= level 1) (string-split level-1-stages ",")] [(= level 2) (string-split level-2-stages ",")] [else #f]))
  (cond
    [(not stages)
     (live "gate all stages start")
     (let-values ([(c t) (capture editor-root nu (append (list "gate/check.nu") (stage-args level)))])
       (live (format "gate all stages done code ~a" c))
       (values c t))]
    [else
     (define results
       (for/list ([s (in-list stages)])
         (live (string-append "gate " s " start"))
         (let-values ([(c t) (capture editor-root nu (list "gate/check.nu" "--only" s))])
           (live (format "gate ~a done code ~a" s c))
           (cons c t))))
     (define all-ok
       (andmap (lambda (r) (and (= (car r) 0) (not (regexp-match? #px"(?m:^CODE [^ ]+ [1-9][0-9]*$)" (cdr r))))) results))
     (values (if all-ok 0 1)
             (string-append (apply string-append (map (lambda (r) (string-append (cdr r) "\n")) results))
                            (if all-ok "light gate: green\n" "light gate: red\n")))]))
