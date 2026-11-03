#lang racket/base
;; One job: the text commands - insert, type, delete, save, journal, replay, select and the cursor moves.

(require racket/list
         racket/path
         racket/string
         "../../buffer/selection.rkt"
         "../../join/protocol.rkt"
         "../../join/hot-path.rkt"
         "../../journal/replay.rkt"
         "../../notation/document.rkt"
         "../../notation/host.rkt"
         "../../notation/where.rkt"
         "../session.rkt"
         "../multi-boxes.rkt")

(provide command-insert-words command-save command-journal command-replay command-move-up command-move-down command-move-left command-move-right command-type command-delete command-select)

;; command-insert-words puts the rest of the line into the text at the
;; end of the buffer. The text is not written to the file yet: the
;; journal holds it until a save.
(define (command-insert-words session words)
  (cons #t
        (answer-line
         (ask session "insert" (hasheq 'text (string-join words " "))))))

;; command-save writes the text to the file and empties the journal: the
;; work is in the file now.
(define (command-save session words)
  (cons #t (answer-line (ask session "save" (hasheq)))))

;; command-journal answers the journal's records: every edit, in order.
(define (command-journal session words)
  (cons #t (answer-line (ask session "journal" (hasheq)))))

;; command-replay rebuilds the state after a crash and reports what is
;; waiting: the counts and the journal's records. The text itself is what
;; the show command answers.
(define (command-replay session words)
  (cons #t
        (replay-report
         (replay-state (session-file session) (session-journal session)))))

;; command-move moves the cursor a way. The hot path holds the text, so
;; it is asked where the cursor goes.
(define (command-move session direction)
  (define answer
    (ask session "move" (hasheq 'at (number->string (the-point session))
                            'direction direction)))
  (if (response-ok answer)
      (begin
        (move-to session (string->number (hash-ref (response-data answer) 'at "0")))
        ;; in the select layer the cursor GROWS the region: that is what
        ;; a selection is, and the region is the buffer area's
        (when (string=? (the-layer session) "select")
          (set-box! (session-selection session)
                     (grow-region (the-selection session) (the-point session))))
        (cons #t (format "point=~a" (the-point session))))
      (cons #t "the cursor could not be moved")))

;; command-move-up moves the cursor up a line.
(define (command-move-up session words) (command-move session "up"))

;; command-move-down moves the cursor down a line.
(define (command-move-down session words) (command-move session "down"))

;; command-move-left moves the cursor left a character.
(define (command-move-left session words) (command-move session "left"))

;; command-move-right moves the cursor right a character.
(define (command-move-right session words) (command-move session "right"))

;; command-type puts text into the buffer where the cursor stands, and
;; journals the edit with the place it happened. This is the command
;; the keys of the insert layer run.
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

;; command-delete takes the character BEFORE the cursor out of the buffer,
;; and journals the edit. The start of that character is asked of the hot
;; path (the "move" left answer), so a character of several bytes is taken
;; whole and never split: the buffer is bytes, and a point inside a
;; character is not a point. The point moves back with the character, so a
;; second backspace takes the one before it. At the start of the text there
;; is nothing before the point, and the command says so instead of taking
;; the character in front of it.
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

;; command-select turns the selection on where the cursor stands, and
;; answers the text of the region.
(define (command-select session words)
  (select-from session (the-point session))
  (cons #t (selection-text session)))
