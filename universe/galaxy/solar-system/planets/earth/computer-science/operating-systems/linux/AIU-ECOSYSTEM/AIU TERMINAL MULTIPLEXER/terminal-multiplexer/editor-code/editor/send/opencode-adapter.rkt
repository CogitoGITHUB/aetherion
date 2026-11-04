#lang racket/base

(require json
         net/base64
         racket/bytes
         racket/list
         racket/port
         racket/string
         "../machine/http.rkt")

(struct opencode-client (base-url user password directory) #:transparent)

(define default-url "http://127.0.0.1:4096")

(define (client-from-environment)
  (opencode-client (env-text "AIU_AGENT_URL" default-url)
                   (env-text "AIU_AGENT_USER" "opencode")
                   (env-text "AIU_AGENT_PASSWORD" "")
                   (env-text "AIU_AGENT_DIRECTORY" ".")))

(define (env-text name fallback)
  (define value (getenv name))
  (if (and value (not (string=? value ""))) value fallback))

(define (client-name client)
  "opencode")

(define (client-headers client)
  (list (cons "Host" (url-host-part (opencode-client-base-url client)))
        (cons "Authorization" (basic-authorization (opencode-client-user client)
                                                 (opencode-client-password client)))
        (cons "Content-Type" "application/json")
        (cons "X-Opencode-Directory" (opencode-client-directory client))))

(define (url-host-part base-url)
  (define without-scheme (string-replace base-url #rx"^[a-z]+://" ""))
  (car (string-split without-scheme ":")))

(define (basic-authorization user password)
  (define encoded (bytes->string/utf-8 (base64-encode (string->bytes/utf-8 (string-append user ":" password)))))
  (string-append "Basic " (string-replace encoded "\r\n" "")))

(define (client-version client)
  (define reply (call client "GET" "/api/info" #f))
  (if reply
      (let ([parsed (json-of (http-reply-body reply))])
        (if (hash? parsed) (hash-ref parsed 'version "unverified") "unverified"))
      "unverified"))

(define (call client method path body)
  (http-call (opencode-client-base-url client)
             method
             path
             (client-headers client)
             (if body (json-text body) "")))

(define (json-text value)
  (call-with-output-string (lambda (port) (write-json value port))))

(define (json-of text)
  (with-handlers ([exn:fail? (lambda (why) #f)])
    (read-json (open-input-string text))))

(define (client-open client)
  (define reply
    (call client "POST" "/api/session"
                 (hasheq 'title "the aiu editor"
                         'permissions (list (hasheq 'action "edit" 'resource "*" 'effect "ask")
                                            (hasheq 'action "bash" 'resource "*" 'effect "ask")
                                            (hasheq 'action "webfetch" 'resource "*" 'effect "ask")))))
  (if (and reply (<= 200 (http-reply-status reply) 299))
      (let ([parsed (json-of (http-reply-body reply))])
        (define data (if (hash? parsed) (hash-ref parsed 'data #f) #f))
        (define id (if (hash? data) (hash-ref data 'id #f) #f))
        (if id
            (values id #f)
            (values #f (client-refusal "the server did not answer with a session"))))
      (values #f (client-refusal "the agent is not reachable: the server refused the call"))))

(define (client-deliver client session-id text)
  (define reply (call client "POST" (session-path session-id "/prompt") (hasheq 'text text)))
  (if (and reply (<= 200 (http-reply-status reply) 299))
      (let ([parsed (json-of (http-reply-body reply))])
        (if (hash? parsed)
            (values (hash-ref parsed 'data #f) #f)
            (values #f (client-refusal "the server did not answer with a message"))))
      (values #f (client-refusal "the agent refused the bundle"))))

(define (client-open-feed client)
  (http-open-stream (opencode-client-base-url client)
                    "GET"
                    "/api/event"
                    (client-headers client)))

(define (client-turn stream session-id)
  (if (not stream)
      (values #f #f (client-refusal "the agent is not reachable: the event feed did not open"))
      (let loop ([events '()] [text ""])
        (define line (http-stream-line stream))
        (cond
          [(or (eof-object? line) (not line))
           (close-input-port (http-stream-port stream))
           (values (reverse events) text #f)]
          [else
           (define event (event-of-line line))
           (cond
             [(not event) (loop events text)]
             [(not (event-of-session? event session-id)) (loop events text)]
             [else
              (define type (hash-ref event 'type ""))
              (cond
                [(string=? type "session.text.delta")
                 (loop (cons event events)
                       (string-append text (hash-ref (hash-ref event 'data #f) 'delta "")))]
                [(string=? type "permission.asked")
                 (close-input-port (http-stream-port stream))
                 (values (reverse (cons event events)) text #f)]
                [(or (string=? type "session.execution.succeeded")
                     (string=? type "session.execution.failed"))
                 (close-input-port (http-stream-port stream))
                 (values (reverse (cons event events)) text #f)]
                [else (loop (cons event events) text)])])]))))

(define (event-of-line line)
  (if (string-prefix? (string-trim line) "data:")
      (with-handlers ([exn:fail? (lambda (why) #f)])
        (json-of (string-trim (substring line 5))))
      #f))

(define (event-of-session? event session-id)
  (or (equal? (hash-ref (hash-ref event 'data #f) 'sessionID #f) session-id)
      (equal? (hash-ref event 'sessionID #f) session-id)))

(define (client-permissions client session-id)
  (define reply (call client "GET" (session-path session-id "/permission") #f))
  (if (and reply (<= 200 (http-reply-status reply) 299))
      (let ([parsed (json-of (http-reply-body reply))])
        (if (hash? parsed) (hash-ref parsed 'data '()) '()))
      '()))

(define (ask-files ask)
  (define resources (hash-ref ask 'resources '()))
  (define files (hash-ref (hash-ref ask 'metadata #f) 'files '()))
  (append resources
          (for/list ([file (in-list files)])
            (hash-ref file 'file ""))))

(define (client-reply client session-id request-id decision)
  (define reply (call client "POST"
                            (session-path session-id (string-append "/permission/" request-id "/reply"))
                            (hasheq 'decision decision)))
  (if (and reply (<= 200 (http-reply-status reply) 299))
      (values #t #f)
      (values #f (client-refusal "the agent refused the answer to the permission ask"))))

(define (client-cancel client session-id)
  (define reply (call client "POST" (session-path session-id "/interrupt") #f))
  (if (and reply (<= 200 (http-reply-status reply) 299))
      (values #t #f)
      (values #f (client-refusal "the agent could not be cancelled"))))

(define (client-end client session-id)
  (define reply (call client "DELETE" (session-path session-id "") #f))
  (if (and reply (<= 200 (http-reply-status reply) 299))
      (values #t #f)
      (values #f (client-refusal "the session could not be ended"))))

(define (session-path session-id suffix)
  (string-append "/api/session/" session-id suffix))

(define (client-refusal what)
  (hash 'kind "err-no-agent"
        'who "opencode"
        'what what
        'what_to_do "start the agent's server on the loopback, or set AIU_AGENT_URL and AIU_AGENT_PASSWORD"))

(provide opencode-client
         opencode-client-base-url
         opencode-client-user
         opencode-client-password
         opencode-client-directory
         client-from-environment
         client-name
         client-version
         client-headers
         client-open
         client-deliver
         client-open-feed
         client-turn
         client-permissions
         ask-files
         client-reply
         client-cancel
         client-end
         client-refusal)
