#lang racket/base

(require net/url
         racket/bytes
         racket/list
         racket/port
         racket/string
         racket/tcp)

(struct http-reply (status headers body) #:transparent)

(struct byte-reader (port buffer) #:transparent #:mutable)

(struct http-stream (port chunked? reader buffer) #:transparent)

(define (http-call base-url method path headers body)
  (with-handlers ([exn:fail? (lambda (why) #f)])
    (define u (string->url base-url))
    (define-values (in out) (tcp-connect (url-host u) (url-port u)))
    (dynamic-wind
     void
     (lambda ()
       (write-request out method path headers body #f)
       (define reader (new-byte-reader in))
       (define status (read-status reader))
       (define reply-headers (read-headers reader))
       (http-reply status reply-headers (read-body reader reply-headers)))
     (lambda () (close-input-port in)))))

(define (http-open-stream base-url method path headers)
  (with-handlers ([exn:fail? (lambda (why) #f)])
    (define u (string->url base-url))
    (define-values (in out) (tcp-connect (url-host u) (url-port u)))
    (write-request out method path headers "" #t)
    (define reader (new-byte-reader in))
    (define status (read-status reader))
    (define reply-headers (read-headers reader))
    (if (and (>= status 200) (< status 300))
        (http-stream in (chunked-body? reply-headers) reader (box ""))
        (begin (close-input-port in) #f))))

(define (write-request out method path headers body keep-alive?)
  (fprintf out "~a ~a HTTP/1.1\r\n" method path)
  (for ([h (in-list headers)])
    (fprintf out "~a: ~a\r\n" (car h) (cdr h)))
  (when (not (string=? body ""))
    (fprintf out "Content-Length: ~a\r\n" (string-length body)))
  (fprintf out "Connection: ~a\r\n\r\n" (if keep-alive? "keep-alive" "close"))
  (when (not (string=? body ""))
    (display body out))
  (flush-output out))

(define (new-byte-reader port)
  (byte-reader port #""))

(define (reader-refill! reader)
  (define more (read-bytes 1 (byte-reader-port reader)))
  (if (eof-object? more)
      #f
      (begin
        (set-byte-reader-buffer! reader (bytes-append (byte-reader-buffer reader) more))
        #t)))

(define (reader-line reader)
  (let loop ()
    (define buffer (byte-reader-buffer reader))
    (define index (index-of-byte buffer (char->integer #\newline)))
    (if index
        (let ([line (bytes->string/utf-8 (subbytes buffer 0 index))])
          (set-byte-reader-buffer! reader (subbytes buffer (add1 index) (bytes-length buffer)))
          (drop-carriage-return line))
        (if (reader-refill! reader)
            (loop)
            (let ([rest (byte-reader-buffer reader)])
              (set-byte-reader-buffer! reader #"")
              (if (zero? (bytes-length rest)) #f (bytes->string/utf-8 rest)))))))

(define (reader-bytes reader size)
  (let loop ([out #""])
    (define have (bytes-length out))
    (cond
      [(>= have size) (bytes->string/utf-8 (subbytes out 0 size))]
      [else
       (define buffer (byte-reader-buffer reader))
       (define take (min (- size have) (bytes-length buffer)))
       (set-byte-reader-buffer! reader (subbytes buffer take (bytes-length buffer)))
       (if (and (= take 0) (not (reader-refill! reader)))
           (bytes->string/utf-8 out)
           (loop (bytes-append out (subbytes buffer 0 take))))])))

(define (reader-rest reader)
  (let loop ([out (byte-reader-buffer reader)])
    (set-byte-reader-buffer! reader #"")
    (define more (read-bytes 1 (byte-reader-port reader)))
    (if (eof-object? more)
        (bytes->string/utf-8 out)
        (loop (bytes-append out more)))))

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

(define (read-status reader)
  (define line (reader-line reader))
  (if (not line) 0 (status-of-line line)))

(define (status-of-line line)
  (define parts (string-split line " "))
  (if (< (length parts) 2)
      0
      (string->number (cadr parts))))

(define (read-headers reader)
  (let loop ([out '()])
    (define line (reader-line reader))
    (cond
      [(not line) (reverse out)]
      [(string=? (string-trim line) "") (reverse out)]
      [else (loop (cons (header-pair line) out))])))

(define (header-pair line)
  (define parts (string-split line ":"))
  (if (< (length parts) 2)
      (cons "" "")
      (cons (string-trim (car parts))
            (string-trim (string-join (cdr parts) ":")))))

(define (header-value headers name)
  (define found
    (findf (lambda (h) (string=? (string-downcase (car h)) (string-downcase name)))
           headers))
  (if found (cdr found) #f))

(define (chunked-body? headers)
  (define encoding (header-value headers "transfer-encoding"))
  (and encoding (string-contains? (string-downcase encoding) "chunked")))

(define (http-stream-line stream)
  (if (http-stream-chunked? stream)
      (chunked-line (http-stream-reader stream) (http-stream-buffer stream))
      (reader-line (http-stream-reader stream))))

(define (chunked-line reader buffer)
  (let loop ()
    (define parts (first-line (unbox buffer)))
    (if (car parts)
        (begin (set-box! buffer (cdr parts)) (car parts))
        (if (fill-chunk! reader buffer)
            (loop)
            #f))))

(define (first-line text)
  (let loop ([i 0])
    (cond
      [(>= i (string-length text)) (cons #f #f)]
      [(char=? (string-ref text i) #\newline)
       (cons (substring text 0 i) (substring text (add1 i)))]
      [else (loop (add1 i))])))

(define (fill-chunk! reader buffer)
  (define size-line (reader-line reader))
  (cond
    [(not size-line) (set-box! buffer "") #f]
    [(string=? (string-trim size-line) "") (fill-chunk! reader buffer)]
    [else
     (define size (chunk-size size-line))
     (cond
       [(not size) (set-box! buffer "") #f]
       [(= size 0) (set-box! buffer "") #f]
       [else
        (define chunk (reader-bytes reader size))
        (reader-line reader)
        (set-box! buffer (string-append (unbox buffer) chunk))
        #t])]))

(define (read-body reader headers)
  (define encoding (header-value headers "transfer-encoding"))
  (cond
    [(and encoding (string-contains? (string-downcase encoding) "chunked"))
     (read-chunks reader)]
    [else
     (define length
       (string->number (or (header-value headers "content-length") "0")))
     (if (> length 0)
         (reader-bytes reader length)
         (reader-rest reader))]))

(define (read-chunks reader)
  (let loop ([out ""])
    (define line (reader-line reader))
    (cond
      [(or (not line) (string=? (string-trim line) "")) out]
      [else
       (define size (chunk-size line))
       (define chunk (if (> size 0) (reader-bytes reader size) ""))
       (reader-line reader)
       (loop (string-append out chunk))])))

(define (chunk-size line)
  (string->number (string-trim (car (string-split line ";"))) 16))

(provide http-reply
         http-reply-status
         http-reply-headers
         http-reply-body
         http-stream
         http-stream-port
         http-stream-line
         http-call
         http-open-stream
         header-value)
