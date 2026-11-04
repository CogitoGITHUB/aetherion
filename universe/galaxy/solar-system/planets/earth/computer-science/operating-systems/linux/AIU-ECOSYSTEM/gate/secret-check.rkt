#lang racket/base

(require racket/file
         racket/list
         racket/port
         racket/string
         (file "../AIU EDITOR/text-editor/editor/machine/directories-shared.rkt")
         (file "../AIU EDITOR/text-editor/editor/security/redact.rkt")
         (file "../AIU EDITOR/text-editor/editor/send/bundle.rkt"))

(define the-secret "api_key = sk-0123456789abcdef")

(define the-value "sk-0123456789abcdef")

(define credential-names
  '("api_key" "api-key" "apikey" "password" "passwd" "secret" "token"
    "authorization" "sk-" "bearer " "-----begin"))

(define (holds-secret? line)
  (define lowered (string-downcase line))
  (define named
    (for/or ([name (in-list credential-names)])
      (string-contains? lowered (string-downcase name))))
  (and named (carries-value? line)))

(define (holding-line text)
  (for/or ([line (in-list (string-split text "\n"))])
    (and (holds-secret? line) line)))

(define (carries-value? line)
  (define at
    (let ([colon (index-of line ":")]
          [equals (index-of line "=")])
      (cond
        [(and (not colon) (not equals)) #f]
        [(and colon (not equals)) colon]
        [(and (not colon) equals) equals]
        [else (min colon equals)])))
  (and at
       (let ([value (string-trim (substring line (add1 at) (string-length line)))])
         (and (not (string=? value ""))
              (not (string=? value "[redacted]"))
              (not (string=? value "[redacted];"))))))

(define (index-of line piece)
  (let loop ([at 0])
    (cond
      [(> (+ at (string-length piece)) (string-length line)) #f]
      [(string=? (substring line at (+ at (string-length piece))) piece) at]
      [else (loop (add1 at))])))

(define (main)
  (define problems '())

  (define bundle
    (make-bundle "aiu-editor" "aiu-ecosystem" "opencode"
                 (string-append "the first line\n" the-secret "\nthe last line")
                 "/tmp/aiu-bundle-check.txt"
                 0
                 #f
                 "proving the seam on a real bundle"))
  (define text (bundle-text bundle))

  (unless (holds-secret? text)
      (set! problems (cons "the bundle did not hold the secret the check put in it" problems)))

  (define redacted (redact-text text))
  (when (string-contains? redacted the-value)
      (set! problems (cons (format "the secret survived the seam: ~a" redacted) problems)))
  (unless (string-contains? redacted "[redacted]")
      (set! problems (cons "the seam did not say that something was hidden" problems)))
  (define left (holding-line redacted))
  (when left
      (set! problems (cons (format "the seam left a credential with a value in it: ~a" left) problems)))

  (for ([file (in-list (state-files))])
    (for ([line (in-list (lines-of file))])
      (when (holds-secret? line)
        (set! problems (cons (format "a secret lies on disk: ~a: ~a" file line) problems)))))

  (if (null? problems)
      (begin
        (displayln "OK secret-check — a real bundle comes out of the seam clean, and nothing on disk holds a secret")
        (exit 0))
      (begin
        (for ([problem (in-list problems)]) (displayln (format "SECRET — ~a" problem)))
        (displayln (format "SECRET — ~a problems" (length problems)))
        (exit 1))))

(define (state-files)
  (define dir (state-dir))
  (if (not (file-exists? dir))
      '()
      (for/list ([entry (in-list (directory-list dir #:follow-links #f))])
        (define path (build-path dir entry))
        (cond
          [(directory-exists? path) (state-files-in path)]
          [(file-exists? path) (list path)]
          [else '()]))))

(define (state-files-in dir)
  (for/list ([entry (in-list (directory-list dir #:follow-links #f))])
    (define path (build-path dir entry))
    (cond
      [(directory-exists? path) (state-files-in path)]
      [(file-exists? path) (list path)]
      [else '()])))

(define (lines-of path)
  (with-handlers ([exn:fail? (lambda (why) '())])
    (call-with-input-file path
      (lambda (port)
        (let loop ([out '()])
          (define line (read-line port))
          (if (eof-object? line)
              (reverse out)
              (loop (cons line out))))))))

(module+ main
  (main))
