#lang racket/base

(define (file-name-from-path p)
  (let-values ([(base name dir?) (split-path p)])
    (and (not dir?) (path? name) name)))

(define (path-only p)
  (let-values ([(base name dir?) (split-path p)])
    (cond [dir? (if (path? p) p (string->path p))]
          [(path? base) base]
          [else #f])))

(define (path-parts p)
  (let loop ([q (simplify-path (path->complete-path p) #f)] [acc null])
    (let-values ([(base name dir?) (split-path q)])
      (if (path? base) (loop base (cons name acc)) (cons name acc)))))

(define (find-relative-path root file)
  (let loop ([a (path-parts root)] [b (path-parts file)])
    (cond [(and (pair? a) (pair? b) (equal? (car a) (car b))) (loop (cdr a) (cdr b))]
          [(and (pair? a) (equal? (length a) (length (path-parts root)))) file]
          [else (apply build-path (append (map (lambda (x) (quote up)) a) (if (null? b) (list (quote same)) b)))])))

(define (with-output-to-string thunk)
  (let ([o (open-output-string)])
    (parameterize ([current-output-port o]) (thunk))
    (get-output-string o)))

(define (open-output-nowhere)
  (make-output-port (quote nowhere) always-evt
                    (lambda (s start end non-block? breakable?) (- end start))
                    void))

(provide file-name-from-path path-only find-relative-path
         with-output-to-string open-output-nowhere)

(define (port->lines in)
  (let loop ([acc null])
    (let ([l (read-line in (quote any))])
      (if (eof-object? l) (reverse acc) (loop (cons l acc))))))

(define (port->bytes in)
  (let ([o (open-output-bytes)])
    (let loop ()
      (let ([b (read-bytes 4096 in)])
        (unless (eof-object? b) (write-bytes b o) (loop))))
    (get-output-bytes o)))

(define (port->string in)
  (bytes->string/utf-8 (port->bytes in) #\?))

(define (call-with-output-string f)
  (let ([o (open-output-string)]) (f o) (get-output-string o)))

(provide port->lines port->bytes port->string call-with-output-string)
