#lang racket/base
;; One job: the session - the struct that carries the state of one editing
;; session, its accessors, and the one question every command asks the hot
;; path. It requires no command: commands.rkt requires this file and passes
;; every name on, so the areas above keep their one require.

(require racket/list
         racket/path
         racket/string
         "../buffer/selection.rkt"
         "../join/protocol.rkt"
         "../join/hot-path.rkt")

;; session is the state of one editing session: the file being edited, the
;; journal that holds the work not saved yet, and the point — where the
;; cursor stands — and the selection, which is the region around the
;; point when a selection is on. The point and the selection are boxes,
;; because a command changes them.
(struct session (file journal point selection layer level view-top) #:transparent)

;; name<? orders two names, whether they are symbols or strings: the table
;; of commands is keyed by strings and the answers come back keyed by
;; symbols, and both must read in the same order.
(define (name<? a b)
  (string<? (if (symbol? a) (symbol->string a) a)
            (if (symbol? b) (symbol->string b) b)))

;; ask sends one request to the hot path for this session and answers the
;; response. The file and the journal are added to every request: the hot
;; path holds no session of its own.
(define (ask session op args)
  (ask-hot op (hash-set (hash-set args 'file (path->string (session-file session)))
                         'journal (path->string (session-journal session)))))

;; session-text answers the text of the buffer as it stands, for the painter:
;; the saved file with the journal's unsaved edits on top.
(define (session-text session)
  (define answer (ask session "show" (hasheq)))
  (if (response-ok answer) (hash-ref (response-data answer) 'text "") ""))

;; answer-line turns one answer from the hot path into one line of text,
;; with the names in a fixed order, so two answers read the same way.
(define (answer-line answer)
  (define data (response-data answer))
  (if (response-ok answer)
      (string-join
       (for/list ([key (sort (hash-keys data) name<?)])
         (format "~a=~a" key (hash-ref data key)))
       " ")
      (format "FAIL ~a" (hash-ref data 'what "the hot path refused the request"))))

;; make-session makes the session of one file: the file itself, the
;; journal that holds the work that is not saved yet, the point, the
;; selection and the layer the editor is in. Nothing else is kept, so the
;; session is the only thing that carries the state between commands.
(define (make-session file journal)
  (session file journal (box 0) (box #f) (box "visual") (box 2) (box 0)))

;; the-layer answers the layer the editor is in: "visual", "write" or
;; "select".
(define (the-layer session)
  (unbox (session-layer session)))

;; set-layer! puts the editor in a layer, and answers the layer.
(define (set-layer! session layer)
  (set-box! (session-layer session) layer)
  layer)

;; the-level answers how much of the editor's own furniture is drawn:
;; level 1 is the mode line and the status, level 2 adds the rest of the
;; pieces, level 3 adds the hints, and level 0 draws nothing at all.
(define (the-level session)
  (unbox (session-level session)))

;; set-level! puts the level and answers it.
(define (set-level! session level)
  (set-box! (session-level session) level)
  level)

;; the-view-top answers the first line the view shows: a rendered page is
;; taller than the screen, so the view scrolls on its own, beside the point.
(define (the-view-top session)
  (unbox (session-view-top session)))

;; set-view-top! puts the view at one line and answers it; a line before the
;; top of the page is the top of the page, and there is no timer in it.
(define (set-view-top! session line)
  (set-box! (session-view-top session) (max 0 line))
  (the-view-top session))

;; the-point answers where the cursor stands in this session.
(define (the-point session)
  (unbox (session-point session)))

;; move-to puts the cursor at a place, and answers the new place.
(define (move-to session at)
  (set-box! (session-point session) at)
  at)

;; the-selection answers the selection of this session, or nothing when
;; no selection is on.
(define (the-selection session)
  (unbox (session-selection session)))

;; select-from puts the start of the selection at a place, and turns the
;; selection on. The selection is a REGION: it runs from that place to
;; the cursor, and the region is the buffer area's.
(define (select-from session at)
  (set-box! (session-selection session) (start-region at))
  at)

;; select-off turns the selection off.
(define (select-off session)
  (set-box! (session-selection session) #f)
  #f)

;; selection-text answers the text of the selection, or the empty text
;; when there is no selection. The hot path holds the text, so it is
;; asked for the region.
(define (selection-text session)
  (define answer
    (region-text (lambda (op args) (ask session op args)) (the-selection session)))
  (if (hash? answer)
      (hash-ref answer 'text "")
      ""))

;; The session, for commands.rkt and every area above it.
(provide session make-session session-file session-journal session-point
         session-selection session-layer session-level
         the-point move-to the-selection select-from select-off selection-text
         the-layer set-layer! the-level set-level! the-view-top set-view-top!
         answer-line session-text ask name<?)
