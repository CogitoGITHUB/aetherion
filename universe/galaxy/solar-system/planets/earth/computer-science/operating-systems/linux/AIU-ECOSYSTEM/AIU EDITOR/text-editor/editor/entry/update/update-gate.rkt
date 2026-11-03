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
;; level-stages-text answers the gate stages of a level and the levels below it, joined by commas, read from gate/levels.txt.
(define (level-stages-text n)
  (define f (build-path editor-root "gate" "levels.txt"))
  (string-join (for/list ([l (in-list (file->lines f))] #:when (regexp-match? #px"^[0-9]+ " l) #:when (<= (string->number (car (string-split l))) n)) (cadr (string-split l))) ","))

(define level-1-stages (level-stages-text 1))

;; level-2-stages add the medium stages, about 60 s more.
(define level-2-stages (level-stages-text 2))

;; stage-args answers the arguments that pick the gate stages of a level; level 3 runs all.
(define (stage-args level)
  (cond [(= level 1) (list "--only" level-1-stages)] [(= level 2) (list "--only" level-2-stages)] [else (list)]))

;; stage-label names the stage set of a level for the report.
(define (stage-label level)
  (cond [(= level 1) "quick stages"] [(= level 2) "quick and medium stages"] [else (format "all ~a stages" (length (string-split (level-stages-text 3) ",")))]))

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
     (define started (for/list ([s (in-list stages)]) (let ([ch (make-channel)]) (thread (lambda () (let-values ([(c t) (capture editor-root nu (list "gate/check.nu" "--only" s))]) (channel-put ch (cons c t))))) ch)))
     (define results
       (for/list ([s (in-list stages)])
         (live (string-append "gate " s " start"))
         (let-values ([(c t) (let ([r (channel-get (list-ref started (index-of stages s)))]) (values (car r) (cdr r)))])
           (live (format "gate ~a done code ~a" s c))
           (cons c t))))
     (define all-ok
       (andmap (lambda (r) (and (= (car r) 0) (not (regexp-match? #px"(?m:^CODE [^ ]+ [1-9][0-9]*$)" (cdr r))))) results))
     (values (if all-ok 0 1)
             (string-append (apply string-append (map (lambda (r) (string-append (cdr r) "\n")) results))
                            (if all-ok "light gate: green\n" "light gate: red\n")))]))
