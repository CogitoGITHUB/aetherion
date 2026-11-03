#lang racket/base

(require json
         racket/file
         racket/list
         racket/port
         racket/string
         "../machine/directories.rkt"
         "../security/security.rkt"
         "capabilities.rkt"
         "dispatch/dispatch.rkt"
         "documents.rkt")

(define protocol-version "2024-11-05")

(define rule-gate
  "rule 07: read is free, a change needs the human's token")

(define rule-declaration
  "rule 07: the declaration and the security predicate must agree")

(define (engine-token)
  (define from-env (getenv "AIU_EDITOR_TOKEN"))
  (if (and from-env (not (string=? from-env "")))
      from-env
      (token-from-file)))

(define (token-from-file)
  (define path (build-path (state-dir) "permit-token"))
  (if (not (file-exists? path))
      ""
      (with-handlers ([exn:fail? (lambda (why) "")])
        (define line (read-line (open-input-file path)))
        (if (eof-object? line) "" (string-trim line)))))

(define (token-given? arguments)
  (define given (hash-ref arguments 'confirm ""))
  (define own (engine-token))
  (and (string? given)
       (not (string=? given ""))
       (not (string=? own ""))
       (string=? given own)))

(define (main)
  (define refused
    (let loop ([refused #f])
      (define line (read-line (current-input-port)))
      (if (eof-object? line)
          refused
          (let* ([answer (handle-request line)]
                 [said (or refused (refusal-in? answer))])
            (when answer
              (displayln answer)
              (flush-output (current-output-port)))
            (loop said)))))
  (exit (if refused exit-refusal exit-ok)))

(define (refusal-in? line)
  (define env (envelope-in line))
  (and env
       (hash? (hash-ref env 'refusal #f))
       (not (null? (hash-ref env 'refusal '())))))

(define (handle-request line)
  (define request
    (with-handlers ([exn:fail? (lambda (why) #f)])
      (read-json (open-input-string line))))
  (if (not (hash? request))
      (json-line (jsonrpc-error #f -32700 "the request is not JSON"))
      (let ([id (if (hash-has-key? request 'id) (hash-ref request 'id) #f)]
            [method (hash-ref request 'method "")]
            [params (hash-ref request 'params (hash))])
        (define answer (run-method method params))
        (if (not (hash-has-key? request 'id))
            #f
            (json-line (jsonrpc-answer id answer))))))

(define (run-method method params)
  (cond
    [(string=? method "initialize")
     (hash 'result
           (hash 'protocolVersion protocol-version
                 'capabilities (hash 'tools (hash))
                 'serverInfo (hash 'name program-name 'version envelope-version)))]
    [(string=? method "ping") (hash 'result (hash))]
    [(string=? method "tools/list") (hash 'result (hash 'tools (tool-list)))]
    [(string=? method "tools/call") (hash 'result (tool-call params))]
    [else (hash 'error (hash 'code -32601
                              'message (format "there is no method named ~a" method)))]))

(define (tool-list)
  (for/list ([cap (in-list the-capabilities)])
    (hash 'name (capability-name cap)
          'description (capability-description cap)
          'inputSchema
          (hash 'type "object"
                'properties
                (hash 'args (hash 'type "array"
                                   'description "the arguments of the command, in order")
                      'confirm (hash 'type "string"
                                     'description "the human's token; a change needs it"))
                'required (if (capability-mutating cap) '("confirm") '())))))

(define (tool-call params)
  (define name (hash-ref params 'name ""))
  (define arguments (hash-ref params 'arguments (hash)))
  (define cap (capability-of name))
  (cond
    [(not cap)
     (mcp-error -32602 (format "there is no tool named ~a" name))]
    [(not (declaration-agrees? name))
     (mcp-refusal
      (refusal-document "tool" rule-declaration
                        (format "the declaration and the security predicate disagree about ~a, so it was refused"
                                name)))]
    [(and (capability-mutating cap) (not (token-given? arguments)))
     (mcp-refusal
      (refusal-document "tool" rule-gate
                        (format "~a changes the tree, so it needs the human's token, and it was refused"
                                name)))]
    [else
     (mcp-result
      (make-document "tool" #t
                     (hash 'text (run-the-tool name (tool-args arguments)))
                     #f
                     '()))]))

(define (tool-args arguments)
  (define raw (hash-ref arguments 'args '()))
  (if (list? raw)
      (map (lambda (v) (if (string? v) v (format "~a" v))) raw)
      '()))

(define (run-the-tool name args)
  (define out (open-output-string))
  (parameterize ([current-output-port out])
    (run-verb name args))
  (get-output-string out))

(define (mcp-result doc)
  (hash 'content (list (hash 'type "text" 'text (document-line doc)))
        'isError (not (document-ok doc))))

(define (mcp-refusal doc)
  (mcp-result doc))

(define (mcp-error code message)
  (hash 'error (hash 'code code 'message message)))

(define (jsonrpc-answer id answer)
  (if (hash-has-key? answer 'error)
      (hash 'jsonrpc "2.0" 'id id 'error (hash-ref answer 'error))
      (hash 'jsonrpc "2.0" 'id id 'result (hash-ref answer 'result #f))))

(define (jsonrpc-error id code message)
  (hash 'jsonrpc "2.0" 'id id 'error (hash 'code code 'message message)))

(define (json-line value)
  (define out (open-output-string))
  (write-json value out)
  (get-output-string out))

(define (envelope-in line)
  (if (not line)
      #f
      (let* ([parsed
              (with-handlers ([exn:fail? (lambda (why) #f)])
                (read-json (open-input-string line)))]
             [result (if (hash? parsed) (hash-ref parsed 'result #f) #f)]
             [content (if (hash? result) (hash-ref result 'content '()) '())]
             [first (if (null? content) #f (car content))]
             [text (if (hash? first) (hash-ref first 'text "") "")])
        (if (string=? text "")
            #f
            (with-handlers ([exn:fail? (lambda (why) #f)])
              (read-json (open-input-string text)))))))

(module+ main
  (main))

(provide protocol-version
         rule-gate
         rule-declaration
         engine-token
         main
         handle-request
         run-method
         tool-list
         tool-call
         run-the-tool
         refusal-in?
         envelope-in)
