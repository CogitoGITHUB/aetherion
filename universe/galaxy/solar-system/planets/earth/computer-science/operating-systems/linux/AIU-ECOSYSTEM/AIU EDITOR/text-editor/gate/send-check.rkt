#lang racket/base

(require json
         racket/async-channel
         racket/bytes
         racket/list
         racket/port
         racket/string
         racket/tcp
         "../editor/buffer/selection.rkt"
         "../editor/send/bundle.rkt"
         "../editor/send/opencode-adapter.rkt")

(define session-id "ses_gate")

(define agent-text "the gate agent answers")

(define region-body "the region the human marked")

(define delivered (box ""))

(define bundle-arrived (make-channel))

(define (json-text value)
  (call-with-output-string (lambda (port) (write-json value port))))

(define (byte-count text)
  (bytes-length (string->bytes/utf-8 text)))

(struct stub-reader (port buffer) #:transparent #:mutable)

(define (reader-refill! reader)
  (define more (read-bytes 1 (stub-reader-port reader)))
  (if (eof-object? more)
      #f
      (begin
        (set-stub-reader-buffer! reader (bytes-append (stub-reader-buffer reader) more))
        #t)))

(define (reader-line reader)
  (let loop ()
    (define buffer (stub-reader-buffer reader))
    (define index (index-of-byte buffer (char->integer #\newline)))
    (if index
        (let ([line (bytes->string/utf-8 (subbytes buffer 0 index))])
          (set-stub-reader-buffer! reader (subbytes buffer (add1 index) (bytes-length buffer)))
          (drop-carriage-return line))
        (if (reader-refill! reader)
            (loop)
            (let ([rest (stub-reader-buffer reader)])
              (set-stub-reader-buffer! reader #"")
              (if (zero? (bytes-length rest)) #f (bytes->string/utf-8 rest)))))))

(define (reader-bytes reader size)
  (let loop ([out #""])
    (define have (bytes-length out))
    (cond
      [(>= have size) (bytes->string/utf-8 (subbytes out 0 size))]
      [else
       (define buffer (stub-reader-buffer reader))
       (define take (min (- size have) (bytes-length buffer)))
       (set-stub-reader-buffer! reader (subbytes buffer take (bytes-length buffer)))
       (if (and (= take 0) (not (reader-refill! reader)))
           (bytes->string/utf-8 out)
           (loop (bytes-append out (subbytes buffer 0 take))))])))

(define (index-of-byte buffer byte)
  (let loop ([i 0])
    (cond
      [(>= i (bytes-length buffer)) #f]
      [(= (bytes-ref buffer i) byte) i]
      [else (loop (add1 i))])))

(define (drop-carriage-return line)
  (define size (string-length line))
  (if (and (> size 0) (char=? (string-ref line (sub1 size)) #\return))
      (substring line 0 (sub1 size))
      line))

(define (open-stub)
  (define listener (tcp-listen 0 4))
  (thread (lambda () (accept-loop listener)))
  (values listener (stub-port listener)))

(define (stub-port listener)
  (call-with-values (lambda () (tcp-addresses listener #t))
    (lambda values (list-ref values 1))))

(define (accept-loop listener)
  (let loop ()
    (define-values (in out)
      (with-handlers ([exn:fail? (lambda (why) (values #f #f))])
        (tcp-accept listener)))
    (when (and in out)
      (thread (lambda ()
                (with-handlers ([exn:fail? (lambda (why)
                                            (fprintf (current-error-port) "the stub failed: ~a\n" (exn-message why)))])
                  (serve-connection in out))))
      (loop))))

(define (serve-connection in out)
  (define reader (stub-reader in #""))
  (define request (reader-line reader))
  (define path (request-path request))
  (define headers (read-headers reader))
  (define body (read-body reader headers))
  (cond
    [(equal? path "/api/session")
     (write-json-reply in out (hasheq 'data (hasheq 'id session-id)))]
    [(string-suffix? path "/prompt")
     (set-box! delivered (prompt-text body))
     (channel-put bundle-arrived #t)
     (write-json-reply in out (hasheq 'data (hasheq 'id "msg_gate")))]
    [(equal? path "/api/event")
     (serve-feed out)]
    [else
     (write-json-reply in out (hasheq 'data (hasheq)))]))

(define (request-path request)
  (if (string? request)
      (let ([parts (string-split request " ")])
        (if (>= (length parts) 2) (cadr parts) ""))
      ""))

(define (read-headers reader)
  (let loop ([out '()])
    (define line (reader-line reader))
    (cond
      [(not line) (reverse out)]
      [(string=? (string-trim line) "") (reverse out)]
      [else
       (define parts (string-split line ":"))
       (loop (if (>= (length parts) 2)
                 (cons (cons (string-trim (car parts))
                              (string-trim (string-join (cdr parts) ":")))
                       out)
                 out))])))

(define (read-body reader headers)
  (define length
    (for/first ([header (in-list headers)]
                #:when (string=? (string-downcase (car header)) "content-length"))
      (string->number (cdr header))))
  (if (and length (> length 0))
      (reader-bytes reader length)
      ""))

(define (prompt-text body)
  (with-handlers ([exn:fail? (lambda (why) "")])
    (define parsed (read-json (open-input-string body)))
    (hash-ref parsed 'text "")))

(define (write-json-reply in out value)
  (define body (json-text value))
  (fprintf out
           "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: ~a\r\nconnection: close\r\n\r\n"
           (byte-count body))
  (display body out)
  (flush-output out)
  (close-input-port in)
  (close-output-port out))

(define (serve-feed out)
  (fprintf out
           "HTTP/1.1 200 OK\r\ncontent-type: text/event-stream\r\ntransfer-encoding: chunked\r\nconnection: keep-alive\r\n\r\n")
  (flush-output out)
  (channel-get bundle-arrived)
  (write-event out (hasheq 'type "session.text.delta"
                           'data (hasheq 'sessionID session-id 'delta agent-text)))
  (write-event out (hasheq 'type "session.execution.succeeded"
                           'data (hasheq 'sessionID session-id)))
  (fprintf out "0\r\n\r\n")
  (flush-output out))

(define (write-event out event)
  (define text (string-append "data: " (json-text event) "\n\n"))
  (fprintf out "~x\r\n" (byte-count text))
  (display text out)
  (fprintf out "\r\n")
  (flush-output out))

(define (client-for port)
  (putenv "AIU_AGENT_URL" (format "http://127.0.0.1:~a" port))
  (putenv "AIU_AGENT_PASSWORD" "the gate's own password")
  (client-from-environment))

(define the-region (region-from 10 25))

(define the-selection
  (hash 'text (region-text (lambda (operation arguments) region-body) the-region)
        'from (region-anchor the-region)
        'to (region-point the-region)))

(define the-bundle
  (make-bundle "aiu-editor" "aiu-ecosystem" "opencode"
               the-selection
               "/tmp/aiu-editor-gate/proof.txt"
               (hash 'line 1)
               #f
               "the gate proves that the region travels"))

(define (run-proofs)
  (define-values (listener port) (open-stub))
  (define client (client-for port))
  (define-values (handle refusal) (client-open client))
  (define feed (client-open-feed client))
  (define-values (message refused) (client-deliver client handle (bundle-text the-bundle)))
  (define-values (events text refused2) (client-turn feed handle))
  (tcp-close listener)
  (list handle feed message refusal refused2 events text (unbox delivered)))

(define (main)
  (define results (run-proofs))
  (define handle (car results))
  (define feed (cadr results))
  (define message (caddr results))
  (define refused (cadddr results))
  (define refused2 (list-ref results 4))
  (define events (list-ref results 5))
  (define text (list-ref results 6))
  (define arrived (list-ref results 7))
  (define proofs
    (list (list "the session opens" (and handle (not refused)))
          (list "the event feed opens" (and feed (not refused2)))
          (list "the bundle is delivered" (and message (not refused)))
          (list "the region travels" (string-contains? arrived region-body))
          (list "the turn ends with the agent's text" (string=? text agent-text))
          (list "the end of the turn is an event"
                (member "session.execution.succeeded"
                        (map (lambda (event) (hash-ref event 'type "")) events)))))
  (define failed (filter (lambda (pair) (not (cadr pair))) proofs))
  (if (null? failed)
      (begin
        (displayln (format "OK send-check — the send holds: ~a" (string-join (map car proofs) "; ")))
        (exit 0))
      (begin
        (displayln (format "BAD send-check — the proof that failed: ~a" (string-join (map car failed) "; ")))
        (exit 3))))

(module+ main
  (main))
