#lang racket/base

(require racket/list
         racket/string
         "../editor/join/live-wire.rkt"
         "../editor/routes/keyboard.rkt"
         "../editor/routes/keymaps.rkt"
         "../editor/routes/routes.rkt")

(define (bytes-of key)
  (define parts
    (for/list ([name (in-list (sequence-of key))])
      (key-bytes name)))
  (if (ormap (lambda (part) (string=? part "")) parts)
      #f
      (string-join parts "")))

(define (check-key layer key)
  (define hex (bytes-of key))
  (cond
    [(not hex)
     (format "the hot path does not know the key ~a of the layer ~a" key layer)]
    [else
     (define names (key-names (hex->bytes hex)))
     (cond
       [(null? names)
        (format "the hot path did not name the key ~a of the layer ~a" key layer)]
       [(not (string=? (string-join names " ") key))
        (format "the hot path named the key ~a of the layer ~a as ~a"
                key layer (string-join names " "))]
       [(not (binding-of layer key))
        (format "the key ~a of the layer ~a is not in the keymap" key layer)]
       [else #f])]))

(define (text-faults)
  (define wanted '(("space" . " ") ("return" . "\n") ("a" . "a") ("tab" . #f)))
  (filter values
          (for/list ([pair (in-list wanted)])
            (define key (car pair))
            (define text (cdr pair))
            (define carries (text-of key))
            (cond
              [(not (equal? carries text))
               (format "the key ~a carries ~s, and it must carry ~s" key carries text)]
              [else
               (define meaning (routing-meaning (route-key key '() "write")))
               (cond
                 [(not (equal? meaning text))
                  (format "the write layer routes ~a to ~s, and the text is ~s" key meaning text)]
                 [else #f])]))))

(define (prefix-faults)
  (define cases
    (list (list "write" (list "tab") #t)
          (list "write" (list "b") #f)
          (list "write" (list "tab" "tab") #f)
          (list "visual" (list "space") #t)
          (list "visual" (list "space" "s") #f)))
  (filter values
          (for/list ([case (in-list cases)])
            (define layer (car case))
            (define names (cadr case))
            (define wanted (caddr case))
            (define got (prefix-of? layer names))
            (if (equal? got wanted)
                #f
                (format "the prefix of ~a in the layer ~a answers ~a, and it must answer ~a"
                        names layer got wanted)))))

(define (main)
  (wire-start)
  (define keys
    (for*/list ([layer (in-list editor-layers)]
                [binding (in-list (keys-of layer))])
      (cons layer (car binding))))
  (define faults
    (append (filter values
                    (for/list ([entry (in-list keys)])
                      (check-key (car entry) (cdr entry))))
            (text-faults)
            (prefix-faults)))
  (if (null? faults)
      (begin
        (printf "OK key-check — ~a keys checked, the decoder and the keymaps agree on every one\n"
                (length keys))
        (wire-stop)
        (exit 0))
      (begin
        (for-each (lambda (fault) (printf "KEY — ~a\n" fault)) faults)
        (printf "KEY — ~a faults in ~a keys\n" (length faults) (length keys))
        (wire-stop)
        (exit 1))))

(module+ main
  (main))
