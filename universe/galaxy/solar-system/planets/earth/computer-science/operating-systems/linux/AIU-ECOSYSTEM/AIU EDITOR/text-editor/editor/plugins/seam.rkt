#lang racket/base

(require json
         racket/file
         racket/list
         racket/path
         racket/string)

(define seam-calls
  '(("describe" "the plugin says what it is and what it provides")
    ("read-file" "the plugin answers the text of a file")
    ("insert-text" "the plugin puts text into the buffer")
    ("save-file" "the plugin writes the buffer to a file")))

(define (seam-call-names)
  (map car seam-calls))

(define (seam-known? call)
  (and (member call (seam-call-names)) #t))

(define (seam-meaning call)
  (define found (assoc call seam-calls))
  (if found (cadr found) #f))

(define (seam-request path call args)
  (ensure-place path)
  (call-with-output-file path
    (lambda (port)
      (write-json (hasheq 'call call 'args args) port)
      (newline port))
    #:exists 'truncate)
  path)

(define (seam-answer path)
  (if (not (file-exists? path))
      #f
      (with-handlers ([exn:fail? (lambda (why) #f)])
        (define text (string-trim (file->string path)))
        (if (string=? text "")
            #f
            (read-json (open-input-string text))))))

(define (ensure-place path)
  (define directory (path-only path))
  (when (not (directory-exists? directory))
    (make-directory* directory))
  path)

(provide seam-calls
         seam-call-names
         seam-known?
         seam-meaning
         seam-request
         seam-answer
         ensure-place)
