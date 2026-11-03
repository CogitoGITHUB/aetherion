#lang racket/base

(require racket/list
         racket/string
         "../../commands/commands.rkt"
         "../../routes/keymaps.rkt"
         "../blocks/blockview.rkt"
         "../bar/bar.rkt"
         "../tabs/finder.rkt")

(define (explorer-lines)
  (define lines (list "the keymap — the editor's own keys"))
  (for ([layer (in-list editor-layers)])
    (set! lines
          (append lines
                  (list (format "  ~a:" layer))))
    (for ([binding (in-list (keys-of layer))])
      (set! lines
            (append lines
                    (list (format "    ~a  ->  ~a"
                                  (car binding)
                                  (cadr binding)))))))
  (define bound
    (map cadr
         (append* (for/list ([layer (in-list editor-layers)])
                    (keys-of layer)))))
  (define typed
    (filter (lambda (name) (not (member name bound)))
            (sort (hash-keys commands) string<?)))
  (when (not (null? typed))
    (set! lines (append lines (list "  the commands you can type:")))
    (for ([name (in-list typed)])
      (set! lines (append lines (list (format "    ~a" name))))))
  (append lines (list "  every command of the table is in this panel")))

(define (command-explorer session words)
  (cons #t (string-join (explorer-lines) "\n")))

(hash-set! commands "explorer" command-explorer)

(provide explorer-lines
         command-explorer)
