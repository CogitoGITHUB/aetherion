#lang racket/base
;; One job: the command table — one name, one function. Each function
;; takes the session and the words of the typed line, and answers whether
;; the session goes on and the line of text to print. What a typed line
;; means is the meaning side's job (rule 09); the text itself belongs to
;; the hot path, which holds the state.
;;
;; The order of this file is the order Racket reads it: every name is
;; defined before anything that uses it at load time, so the table can
;; name the handlers and the names can be sorted.

(require racket/list
         racket/path
         racket/string
         "../buffer/selection.rkt"
         "../join/protocol.rkt"
         "../join/hot-path.rkt"
         "../journal/replay.rkt"
         "../notation/document.rkt"
         "../notation/host.rkt"
         "../notation/where.rkt"
         "session.rkt"
         "multi-boxes.rkt")

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

;; command-help answers the names in the table.
(define (command-help session words)
  (cons #t (string-join command-names ", ")))

;; command-quit ends the session: the answer says goodbye and the go-on
;; flag says no.
(define (command-quit session words)
  (cons #f "bye"))

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

;; command-send sends what is selected to the agent. The send area is ABOVE
;; this one, so this cannot call it: the send area puts its own command
;; here when it loads, and this is only the place it stands until then.
(define (command-send session words)
  (cons #t "the send action is not built yet: the agent boundary lands with the AI link"))

;; command-mode changes the layer the editor is in: the visual layer goes
;; to the write layer and the write layer goes back to the visual one.
;; The owner's key is a double space in the visual layer and a double tab
;; in the write layer, where a space is a typed space.
(define (command-mode session words)
  (define layer (the-layer session))
  (define next (if (string=? layer "write") "visual" "write"))
  (set-layer! session next)
  (cons #t (format "layer: ~a" next)))

;; command-visual-mode puts the editor in the visual layer, the general
;; mode.
(define (command-visual-mode session words)
  (set-layer! session "visual")
  (cons #t "layer: visual"))

;; command-write-mode puts the editor in the write layer, where the keys
;; are text.
(define (command-write-mode session words)
  (set-layer! session "write")
  (cons #t "layer: write"))

;; command-select-mode puts the editor in the select layer, where the
;; selected text is what the commands act on.
(define (command-select-mode session words)
  (set-layer! session "select")
  (cons #t "layer: select"))

;; command-level-up shows one level more of the editor's own rows.
(define (command-level-up session words)
  (cons #t (format "level: ~a" (set-level! session (min 3 (+ (the-level session) 1))))))

;; command-view-up scrolls the rendered view up one line. The view has a
;; place of its own, so reading a long page never moves the point.
(define (command-view-up session words)
  (cons #t (format "view line: ~a" (set-view-top! session (sub1 (the-view-top session))))))

;; command-view-down scrolls the rendered view down one line.
(define (command-view-down session words)
  (cons #t (format "view line: ~a" (set-view-top! session (add1 (the-view-top session))))))

;; command-blocks answers the blocks of the page the session edits, one line
;; each: the name, the lines it covers and its declarations. It is the page as
;; a person reads it, and it is read through the notation engine.
(define (command-blocks session words)
  (define got (page-of (session-file session) (session-journal session)))
  (cons #t (if (page? got) (blocks-text got) (page-refusal-text got))))

;; command-block answers the block the point sits in: the innermost one, so a
;; point inside a section's title answers the title and not the section.
(define (command-block session words)
  (define got (page-of (session-file session) (session-journal session)))
  (if (page? got)
      (let ([b (block-at got (the-point session))])
        (cons #t
              (if b
                  (format "the block: ~a  lines ~a-~a"
                          (block-name b) (block-start-line b) (block-end-line b))
                  "the point is outside every block")))
      (cons #t (page-refusal-text got))))

;; command-check answers the faults of the page: where each one is, what is
;; wrong and what to do about it. A page with no fault says so.
(define (command-check session words)
  (define got (page-of (session-file session) (session-journal session)))
  (cons #t (if (page? got) (faults-text got) (page-refusal-text got))))

;; command-next-block moves the point to the start of the next block, and says
;; where it landed.
(define (command-next-block session words)
  (define got (page-of (session-file session) (session-journal session)))
  (if (page? got)
      (let ([b (block-start-after got (the-point session))])
        (cond
          [b (move-to session (block-start b))
             (cons #t (format "the block: ~a at line ~a" (block-name b) (block-start-line b)))]
          [else (cons #t "the point is past the last block")]))
      (cons #t (page-refusal-text got))))

;; command-block-end moves the point to the end of the block it is in, so a
;; person can see where the block closes.
(define (command-block-end session words)
  (define got (page-of (session-file session) (session-journal session)))
  (if (page? got)
      (let ([b (block-closing got (the-point session))])
        (cond
          [b (move-to session (block-end b))
             (cons #t (format "the end of ~a is line ~a" (block-name b) (block-end-line b)))]
          [else (cons #t "the point is outside every block")]))
      (cons #t (page-refusal-text got))))

;; command-kind answers what kind of file this session edits: an AIU NOTATION
;; page by its extension, or plain text. The extension is the whole test, and
;; it is the notation format's own.
(define (command-kind session words)
  (define name (path->string (session-file session)))
  (cons #t
        (if (string-suffix? name ".aiu")
            "the kind: notation page (.aiu)"
            "the kind: text")))

;; command-table is the table as data: one name and one function per
;; command.
(define command-table
  (hash "insert" command-insert-words
                           "type" command-type
                           "save" command-save
                           "journal" command-journal
                           "replay" command-replay
                           "help" command-help
                           "quit" command-quit
                           "move-up" command-move-up
                           "move-down" command-move-down
                           "move-left" command-move-left
                           "move-right" command-move-right
                           "delete" command-delete
                           "select" command-select
                           "send" command-send
                           "mode" command-mode
                           "visual-mode" command-visual-mode
                           "write-mode" command-write-mode
                           "select-mode" command-select-mode
                           "level-up" command-level-up
                           "view-up" command-view-up
                           "view-down" command-view-down
                           "blocks" command-blocks
                           "block" command-block
                           "check" command-check
                           "next-block" command-next-block
                           "block-end" command-block-end
                           "kind" command-kind))

;; commands is the table: one name, one function. The keys are compared
;; as text, so a name typed on the keyboard finds its function. The table
;; is MUTABLE: an area above this one may add its own command to it.
(define commands
  (let ([table (make-hash)])
    (for ([entry (in-list (hash->list command-table))])
      (hash-set! table (car entry) (cdr entry)))
    table))

;; command-names answers the names in the table, in a fixed order.
(define command-names
  (sort (hash-keys commands) name<?))

;; words-of splits one typed line into its words.
(define (words-of line)
  (filter (lambda (word) (not (string=? word ""))) (string-split line " ")))

;; run-command-words runs one command whose words are already split, and
;; answers whether the session goes on and the line of text to print. It
;; stands beside run-command because the live session's text is not a
;; typed line: a space the person pressed is one word that IS a space,
;; and splitting then rejoining it would turn it into nothing at all.
(define (run-command-words session name words)
  (define handler (hash-ref commands name #f))
  (if handler
      (handler session words)
      (cons #t (format "there is no command named ~a; ask for one of: ~a"
                       name (string-join command-names ", ")))))

;; run-command runs one typed line and answers whether the session goes
;; on, and the line of text to print. A line with no words says nothing
;; and changes nothing.
(define (run-command session line)
  (define words (words-of line))
  (if (null? words)
      (cons #t "")
      (run-command-words session (car words) (cdr words))))

;; The command table, for every area above this one.
(provide commands
         session
         make-session
         session-file
         session-journal
         session-point
         session-selection
         session-layer
         session-level
         the-point
         move-to
         the-selection
         select-from
         select-off
         selection-text
         the-layer
         set-layer!
         the-level
         set-level!
         the-view-top
         set-view-top!
         run-command
         run-command-words
         command-names
         answer-line
         session-text
         ask)

;; move-to is shared with the block view, which puts the point back inside a block.
(provide move-to)

;; kind-filter holds the kind of block that block-up and block-down move between: any, a block name, todo, todo open or todo done. The bar shows it.
(define kind-filter (box "any"))

;; mode-label answers the sub-mode shown in the mode line: visual selection in
;; the select layer, visual navigation when a pick other than any is active,
;; visual general otherwise, and the layer name for every other layer.
(define (mode-label layer)
  (cond [(string=? layer "select") "visual selection"]
        [(string=? layer "visual") (if (string=? (unbox kind-filter) "any") "visual general" "visual navigation")]
        [else layer]))


(provide kind-filter mode-label)
;; unsaved is true while the file has edits that are not saved; the bar and the one line show it.
(define unsaved (box #f))

(provide unsaved)

;; The editor pieces that the undo layer needs: the hot path request, the text, the layer, the point and the file.
(provide ask session-text set-layer! the-point session-file)


;; The multi-cursor state boxes live in multi-boxes.rkt; they are passed on from here.
(provide extra-cursors main-anchor multi-raw-view multi-file multi-lit-hook multi-text-hook
         multi-edit-hook multi-live? multi-raw? multi-clear! multi-drop-selections!)
