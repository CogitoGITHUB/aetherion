#lang racket/base

(require racket/list
         racket/path
         racket/string
         "../../buffer/selection.rkt"
         "../../join/protocol.rkt"
         "../../join/hot-path.rkt"
         "../../journal/replay.rkt"
         "../../bridge/document.rkt"
         "../../bridge/host.rkt"
         "../../bridge/where.rkt"
         "../session.rkt"
         "../multi-boxes.rkt")

(provide command-insert-words command-save command-journal command-replay command-move-up command-move-down command-move-left command-move-right command-type command-delete command-select)

(define (command-insert-words session words)
  (cons #t
        (answer-line
         (ask session "insert" (hasheq 'text (string-join words " "))))))

(define (command-save session words)
  (cons #t (answer-line (ask session "save" (hasheq)))))

(define (command-journal session words)
  (cons #t (answer-line (ask session "journal" (hasheq)))))

(define (command-replay session words)
  (cons #t
        (replay-report
         (replay-state (session-file session) (session-journal session)))))

(define (command-move session direction)
  (define answer
    (ask session "move" (hasheq 'at (number->string (the-point session))
                            'direction direction)))
  (if (response-ok answer)
      (begin
        (move-to session (string->number (hash-ref (response-data answer) 'at "0")))
        (when (string=? (the-layer session) "select")
          (set-box! (session-selection session)
                     (grow-region (the-selection session) (the-point session))))
        (cons #t (format "point=~a" (the-point session))))
      (cons #t "the cursor could not be moved")))

(define (command-move-up session words) (command-move session "up"))

(define (command-move-down session words) (command-move session "down"))

(define (command-move-left session words) (command-move session "left"))

(define (command-move-right session words) (command-move session "right"))

(define (command-type session words)
  (define text (string-join words " "))
  (define at (the-point session))
  (define answer
    (ask session "insert-at" (hasheq 'at (number->string at) 'text text)))
  (if (response-ok answer)
      (begin
        (move-to session (+ at (string-length text)))
        (cons #t (answer-line answer)))
      (cons #t "the text could not be inserted")))

(define (command-delete session words)
  (define at (the-point session))
  (if (zero? at)
      (cons #t "the point is at the start: there is nothing before it to delete")
      (let* ([left (ask session "move"
                        (hasheq 'at (number->string at) 'direction "left"))]
             [before (if (response-ok left)
                         (string->number (hash-ref (response-data left) 'at
                                                   (number->string (sub1 at))))
                         (sub1 at))]
             [answer (ask session "delete-at"
                          (hasheq 'at (number->string before)
                                  'count (number->string (- at before))))])
        (if (response-ok answer)
            (begin
              (move-to session before)
              (cons #t (answer-line answer)))
            (cons #t "the text could not be deleted")))))

(define (command-select session words)
  (select-from session (the-point session))
  (cons #t (selection-text session)))
