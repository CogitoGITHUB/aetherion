#lang racket/base
(require racket/list "layout-tree-shared.rkt")
(provide (struct-out layout-buffer) (struct-out layout-buffer-list)
         layout-buffers-new layout-buffers-update-current layout-buffers-add layout-buffers-next
         layout-buffers-previous layout-buffers-close layout-buffers-rename layout-buffers-names
         layout-buffers-current-index layout-buffers-tab-ids)

(struct layout-buffer (name layout) #:transparent)
(struct layout-buffer-list (buffers current) #:transparent)

(define (layout-buffers-new name tab-id)
  (layout-buffer-list (list (layout-buffer name (layout-new tab-id))) 0))

(define (layout-buffers-current-index state)
  (layout-buffer-list-current state))

(define (current-buffer state)
  (list-ref (layout-buffer-list-buffers state) (layout-buffer-list-current state)))

(define (layout-buffers-update-current state change)
  (define buffers (layout-buffer-list-buffers state))
  (define index (layout-buffer-list-current state))
  (define buffer (list-ref buffers index))
  (layout-buffer-list
   (list-set buffers index (layout-buffer (layout-buffer-name buffer) (change (layout-buffer-layout buffer))))
   index))

(define (layout-buffers-add state name tab-id)
  (define buffers (layout-buffer-list-buffers state))
  (define at (add1 (layout-buffer-list-current state)))
  (layout-buffer-list
   (append (take buffers at) (list (layout-buffer name (layout-new tab-id))) (drop buffers at))
   at))

(define (layout-buffers-next state)
  (define count (length (layout-buffer-list-buffers state)))
  (layout-buffer-list (layout-buffer-list-buffers state)
                      (modulo (add1 (layout-buffer-list-current state)) count)))

(define (layout-buffers-previous state)
  (define count (length (layout-buffer-list-buffers state)))
  (layout-buffer-list (layout-buffer-list-buffers state)
                      (modulo (sub1 (layout-buffer-list-current state)) count)))

(define (layout-buffers-close state)
  (define buffers (layout-buffer-list-buffers state))
  (define index (layout-buffer-list-current state))
  (cond
    [(null? (cdr buffers)) state]
    [else
     (layout-buffer-list (append (take buffers index) (drop buffers (add1 index)))
                         (if (> index 0) (sub1 index) 0))]))

(define (layout-buffers-rename state name)
  (define buffers (layout-buffer-list-buffers state))
  (define index (layout-buffer-list-current state))
  (layout-buffer-list
   (list-set buffers index (layout-buffer name (layout-buffer-layout (list-ref buffers index))))
   index))

(define (layout-buffers-names state)
  (map layout-buffer-name (layout-buffer-list-buffers state)))

(define (layout-buffers-tab-ids state)
  (layout-tab-ids (layout-buffer-layout (current-buffer state))))
