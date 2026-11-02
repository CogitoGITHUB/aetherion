#lang racket/base
;; One job: the tree model of the undo layer - the nodes of the history, their children, their place on the grid, and reading them from git.

(require "undo-git.rkt" (only-in racket/string string-split))

(provide (struct-out undo-node) undo-nodes undo-kids undo-roots undo-order undo-pos undo-rows-count undo-cols-count undo-prefer undo-texts
         undo-older? undo-load-tree! undo-place! undo-layout! undo-parent-of undo-next-of undo-newest)

;; undo-node is one version of the file: the commit, its parent in the history of the file, its time and message.
(struct undo-node (id parent time subject))
;; undo-nodes holds every node by commit id; undo-kids the children of a node, oldest first.
(define undo-nodes (make-hash))
;; undo-kids holds the children of each node, oldest first.
(define undo-kids (make-hash))
;; undo-roots and undo-order hold the node ids: the nodes without a parent, and all nodes oldest first.
(define undo-roots (list))
;; undo-order holds all node ids, oldest first.
(define undo-order (list))
;; undo-pos holds the place of each node on the grid as (column . row); the two counts are its size.
(define undo-pos (make-hash))
;; undo-rows-count is the number of rows of the node grid.
(define undo-rows-count 1)
;; undo-cols-count is the number of columns of the node grid.
(define undo-cols-count 1)
;; undo-prefer remembers, for each node, the child that forward goes to.
(define undo-prefer (make-hash))
;; undo-texts keeps the text of each node once it was read.
(define undo-texts (make-hash))

;; undo-older? orders two node ids by time, then by id.
(define (undo-older? a b)
  (let ([ta (undo-node-time (hash-ref undo-nodes a))] [tb (undo-node-time (hash-ref undo-nodes b))])
    (if (= ta tb) (string<? a b) (< ta tb))))

;; undo-load-tree! reads the history of the file from git and builds the nodes and their children.
(define (undo-load-tree! top rel)
  (hash-clear! undo-nodes)
  (hash-clear! undo-kids)
  (hash-clear! undo-texts)
  (hash-clear! undo-prefer)
  (set! undo-roots (list))
  (set! undo-order (list))
  (let ([revs (undo-git top "rev-list" "--parents" "--topo-order" "aiu-undo" "--glob=refs/aiu-undo-old/*" "--" rel)]
        [meta (undo-git top "log" "--format=%H%x09%at%x09%s" "aiu-undo" "--glob=refs/aiu-undo-old/*" "--" rel)]
        [info (make-hash)])
    (when meta
      (for ([line (in-list (regexp-split #rx"\n" meta))])
        (let ([f (regexp-split #rx"\t" line)])
          (when (>= (length f) 3)
            (hash-set! info (car f) (cons (or (string->number (cadr f)) 0) (caddr f)))))))
    (when revs
      (for ([line (in-list (regexp-split #rx"\n" revs))])
        (let ([w (string-split line)])
          (when (pair? w)
            (let ([i (hash-ref info (car w) (cons 0 ""))])
              (hash-set! undo-nodes (car w)
                         (undo-node (car w) (if (pair? (cdr w)) (cadr w) #f) (car i) (cdr i))))))))
    (for ([(id n) (in-hash undo-nodes)])
      (let ([p (undo-node-parent n)])
        (if (and p (hash-ref undo-nodes p #f))
            (hash-set! undo-kids p (cons id (hash-ref undo-kids p (list))))
            (set! undo-roots (cons id undo-roots)))))
    (for ([k (in-list (hash-keys undo-kids))])
      (hash-set! undo-kids k (sort (hash-ref undo-kids k) undo-older?)))
    (set! undo-roots (sort undo-roots undo-older?))
    (set! undo-order (sort (hash-keys undo-nodes) undo-older?))))

;; undo-place! puts a node and its subtree on the grid: the first child stays on the row of its parent,
;; the others go to new rows below. It answers the last row the subtree used.
(define (undo-place! pos id col row)
  (hash-set! pos id (cons col row))
  (let loop ([ks (hash-ref undo-kids id (list))] [first? #t] [last row])
    (cond [(null? ks) last]
          [else
           (let* ([r (if first? row (add1 last))]
                  [m (undo-place! pos (car ks) (add1 col) r)])
             (loop (cdr ks) #f (max last m)))])))

;; undo-layout! places every node and keeps the size of the grid.
(define (undo-layout!)
  (let ([pos (make-hash)])
    (let loop ([rs undo-roots] [row 0])
      (unless (null? rs)
        (loop (cdr rs) (add1 (undo-place! pos (car rs) 0 row)))))
    (set! undo-pos pos)
    (set! undo-rows-count (add1 (for/fold ([m 0]) ([(k v) (in-hash pos)]) (max m (cdr v)))))
    (set! undo-cols-count (add1 (for/fold ([m 0]) ([(k v) (in-hash pos)]) (max m (car v)))))))

;; undo-parent-of answers the parent of a node, or false.
(define (undo-parent-of id)
  (let ([p (undo-node-parent (hash-ref undo-nodes id))])
    (and p (hash-ref undo-nodes p #f) p)))

;; undo-next-of answers the child that forward goes to: the one last used, else the newest.
(define (undo-next-of id)
  (let ([ks (hash-ref undo-kids id (list))] [pref (hash-ref undo-prefer id #f)])
    (cond [(null? ks) #f]
          [(and pref (member pref ks)) pref]
          [else (car (reverse ks))])))

;; undo-newest answers the newest node.
(define (undo-newest) (car (reverse undo-order)))
