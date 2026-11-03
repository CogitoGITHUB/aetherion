#lang racket/base

(require racket/file
         racket/port
         "protocol.rkt")

(define (call-over-wire program args request [cwd (current-directory)])
  (define work (make-temporary-directory "aiu-wire-~a"))
  (dynamic-wind
    void
    (lambda ()
      (define request-path (build-path work "request.jsonl"))
      (define answer-path (build-path work "answer.jsonl"))
      (define voice-path (build-path work "voice.log"))
      (call-with-output-file request-path #:exists 'truncate
        (lambda (port) (write-message port request)))
      (define exit-code
        (parameterize ([current-directory cwd])
          (let-values ([(sub stdout-in stdin-out voice-or-false)
                        (apply subprocess
                               (append (list (open-output-file answer-path #:exists 'truncate)
                                             (open-input-file request-path)
                                             (open-output-file voice-path #:exists 'truncate)
                                             program)
                                       args
                                       (list request-path answer-path)))])
            (subprocess-wait sub))))
      (or (read-response-file answer-path)
          (response #f (hasheq 'kind "err-no-response"
                              'what (format "the meaning side closed the wire with no answer (exit ~a)" exit-code)
                              'what_to_do (format "run the child by hand and read its voice: ~a" (voice-text voice-path))))))
    (lambda () (delete-directory/files work))))

(define (read-response-file path)
  (if (file-exists? path)
      (call-with-input-file path (lambda (port) (read-response port)))
      #f))

(define (voice-text path)
  (if (file-exists? path) (file->string path) ""))

(provide call-over-wire
         read-response-file
         voice-text)
