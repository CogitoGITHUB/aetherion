#lang racket/base
;; One job: the live session — the keys from the terminal, each one
;; routed and run. Registered in plan/package-tree.org; lands with TODO
;; item 6.
;;
;; The loop is action based: it reads the next byte and the read waits
;; for it. There is NO timer anywhere — not for a key, not for a chord,
;; not for a trigger. A key that is the start of a sequence waits for the
;; next key, and the next key is an action.
;;
;; The decoding is the hot path's job (rule 09): the bytes go over the
;; seam and the hot path answers the name of each key and how many
;; bytes it took. The keymaps and the routing are here (rule 13), so
;; this file looks the name up and runs the command the route names.
;;
;; The terminal is given back exactly as it was found, even when the
;; editor was killed: the settings are saved before the terminal goes
;; raw, and the next run gives it back before it goes raw again.

(require racket/list
         racket/port
         racket/string
         "../narration/print-console.rkt"
         "../commands/commands.rkt"
         "../join/hot-path.rkt"
         "../join/protocol.rkt"
         "../machine/terminal.rkt"
         "../routes/keyboard.rkt"
         "../routes/keymaps.rkt"
         "../routes/routes.rkt")

;; live-session runs the live session on a file: the terminal goes raw,
;; the keys are read and run, and the terminal is given back when the
;; session ends.
(define (live-session file journal)
  (define session (make-session file journal))
  (raw-mode)
  (dynamic-wind
    (lambda () #f)
    (lambda () (key-loop session (current-input-port)))
    (lambda () (restore-settings))))

;; outcome is what one round of the loop did: the bytes that are left
;; for the next round, and whether the session goes on. The bytes are
;; the word "wait" when the keys so far are the start of a sequence and
;; the next key must arrive.
(struct outcome (rest go-on?) #:transparent)

;; read-available answers the bytes that have already arrived, or the word
;; "eof" at the end of the input. It waits for the FIRST byte — that wait is
;; the wait for a key, and no clock decides it — and then takes whatever else
;; is already there. That matters for a key a terminal sends as several bytes
;; in one write: an arrow is escape, "[", "D" in one write, and read one byte
;; at a time it would be decoded as the escape key and two letters.
(define (read-available port chunk)
  (define n (read-bytes-avail! chunk port))
  (cond
    [(eof-object? n) 'eof]
    [(zero? n) '()]
    [else (for/list ([i (in-range n)]) (bytes-ref chunk i))]))

;; key-loop reads the bytes that arrive and runs what they mean. The bytes
;; that have arrived so far are kept: the hot path is asked about all of them,
;; so a key that is the start of a sequence is seen whole. Everything that is
;; already in the buffer is walked before the read waits again, so a paste is
;; typed in the order it was pasted.
(define (key-loop session port)
  (define chunk (make-bytes 1024))
  (let loop ([buffer '()])
    (define arrived (read-available port chunk))
    (unless (eq? arrived 'eof)
      (let walk ([pending (append buffer arrived)])
        (cond
          [(null? pending) (loop '())]
          [else
           (define result (act-on session pending))
           (cond
             [(eq? (outcome-rest result) 'wait)
              (loop pending)]
             [(outcome-go-on? result)
              (walk (outcome-rest result))]
             [else (void)])])))))

;; longest-binding answers how many leading keys of the buffer form a binding:
;; the longest run of them the layer binds. Zero when the layer binds none of
;; the leading runs.
(define (longest-binding layer names)
  (let loop ([k (length names)])
    (cond
      [(zero? k) 0]
      [(binding-of layer (string-join (take names k) " ")) k]
      [else (loop (sub1 k))])))

;; act-on runs what the bytes mean and answers what the round did: the
;; bytes that are left for the next round, and whether the session goes
;; on.
;;
;; The runs are walked from the FRONT, one key at a time. A terminal may hand
;; the editor a whole paste at once, and a chunk is not a command: "tab s tab
;; q" must save and quit, and "one two" must be typed as written. So the
;; longest leading run that is a binding runs first; a run that is the start
;; of a sequence waits for the next key; and otherwise the FIRST key alone is
;; acted on, with the rest of the bytes kept for the next round.
(define (act-on session buffer)
  (define runs (key-runs buffer))
  (cond
    [(null? runs)
     ;; The bytes hold no whole key yet: the next byte is read, and the
     ;; read waits for it. No clock decides this.
     (outcome 'wait #t)]
    [else
     (define names (map car runs))
     (define layer (the-layer session))
     (define matched (longest-binding layer names))
     (cond
       [(> matched 0)
        ;; The longest leading sequence is a command: run it, and keep the
        ;; bytes that came after it.
        (outcome (drop-bytes buffer (take runs matched))
                 (run-it session (binding-of layer (string-join (take names matched) " "))))]
       [(prefix-of? layer names)
        ;; The keys so far are the start of a sequence: the next key is
        ;; waited for, and the wait is an action.
        (outcome 'wait #t)]
       [(and (string=? layer "write") (text-of (car names)))
        ;; In the write layer the keys are text, and the text is what the key
        ;; carries — a space is a space, a return is the newline — never the
        ;; name of the key. One key at a time, so the order cannot change.
        (outcome (drop-bytes buffer (list (car runs)))
                 (run-it-words session "type" (list (text-of (car names)))))]
       [else
        ;; The first key means nothing to anybody: it is said out loud
        ;; and the rest of the bytes are kept.
        (print-line (format "no key is bound to ~a" (car names)))
        (outcome (drop-bytes buffer (list (car runs))) #t)])]))

;; run-it runs one command and answers whether the session goes on. The
;; answer of the command is printed, so a person sees what the key did.
(define (run-it session line)
  (define answer (run-command session line))
  (unless (string=? (cdr answer) "")
    (print-line (cdr answer)))
  (car answer))

;; run-it-words runs one command whose words are already split, and answers
;; whether the session goes on. A key's text is one word even when that word
;; is a space, so the live session hands the words over whole.
(define (run-it-words session name words)
  (define answer (run-command-words session name words))
  (unless (string=? (cdr answer) "")
    (print-line (cdr answer)))
  (car answer))

;; drop-bytes answers the bytes that are left when the keys that were
;; run are taken out of the buffer. The bytes are dropped from the FRONT,
;; because the keys that were run are the first ones in the buffer.
(define (drop-bytes buffer runs)
  (define taken (for/sum ([run (in-list runs)]) (cdr run)))
  (if (>= taken (length buffer))
      '()
      (drop buffer taken)))

;; The live session, for the entry above it.
(provide live-session)
