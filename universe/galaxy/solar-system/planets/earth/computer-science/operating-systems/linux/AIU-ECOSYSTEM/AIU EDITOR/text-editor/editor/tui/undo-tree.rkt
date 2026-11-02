#lang racket/base
;; One job: the tree model of the undo layer - the nodes of the history, their children, their place on the grid, and reading them from git.

(require "undo-git.rkt" (only-in racket/string string-split))

(provide (struct-out ud-node) ud-nodes ud-kids ud-roots ud-order ud-pos ud-rows-count ud-cols-count ud-prefer ud-texts
         ud-older? ud-load-tree! ud-place! ud-layout! ud-parent-of ud-next-of ud-newest)

;; ud-node is one version of the file: the commit, its parent in the history of the file, its time and message.
(struct ud-node (id parent time subject))
;; ud-nodes holds every node by commit id; ud-kids the children of a node, oldest first.
(define ud-nodes (make-hash))
;; ud-kids holds the children of each node, oldest first.
(define ud-kids (make-hash))
;; ud-roots and ud-order hold the node ids: the nodes without a parent, and all nodes oldest first.
(define ud-roots (list))
;; ud-order holds all node ids, oldest first.
(define ud-order (list))
;; ud-pos holds the place of each node on the grid as (column . row); the two counts are its size.
(define ud-pos (make-hash))
;; ud-rows-count is the number of rows of the node grid.
(define ud-rows-count 1)
;; ud-cols-count is the number of columns of the node grid.
(define ud-cols-count 1)
;; ud-prefer remembers, for each node, the child that forward goes to.
(define ud-prefer (make-hash))
;; ud-texts keeps the text of each node once it was read.
(define ud-texts (make-hash))

;; ud-older? orders two node ids by time, then by id.
(define (ud-older? a b)
  (let ([ta (ud-node-time (hash-ref ud-nodes a))] [tb (ud-node-time (hash-ref ud-nodes b))])
    (if (= ta tb) (string<? a b) (< ta tb))))

;; ud-load-tree! reads the history of the file from git and builds the nodes and their children.
(define (ud-load-tree! top rel)
  (hash-clear! ud-nodes)
  (hash-clear! ud-kids)
  (hash-clear! ud-texts)
  (hash-clear! ud-prefer)
  (set! ud-roots (list))
  (set! ud-order (list))
  (let ([revs (ud-git top "rev-list" "--parents" "--topo-order" "aiu-undo" "--glob=refs/aiu-undo-old/*" "--" rel)]
        [meta (ud-git top "log" "--format=%H%x09%at%x09%s" "aiu-undo" "--glob=refs/aiu-undo-old/*" "--" rel)]
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
              (hash-set! ud-nodes (car w)
                         (ud-node (car w) (if (pair? (cdr w)) (cadr w) #f) (car i) (cdr i))))))))
    (for ([(id n) (in-hash ud-nodes)])
      (let ([p (ud-node-parent n)])
        (if (and p (hash-ref ud-nodes p #f))
            (hash-set! ud-kids p (cons id (hash-ref ud-kids p (list))))
            (set! ud-roots (cons id ud-roots)))))
    (for ([k (in-list (hash-keys ud-kids))])
      (hash-set! ud-kids k (sort (hash-ref ud-kids k) ud-older?)))
    (set! ud-roots (sort ud-roots ud-older?))
    (set! ud-order (sort (hash-keys ud-nodes) ud-older?))))

;; ud-place! puts a node and its subtree on the grid: the first child stays on the row of its parent,
;; the others go to new rows below. It answers the last row the subtree used.
(define (ud-place! pos id col row)
  (hash-set! pos id (cons col row))
  (let loop ([ks (hash-ref ud-kids id (list))] [first? #t] [last row])
    (cond [(null? ks) last]
          [else
           (let* ([r (if first? row (add1 last))]
                  [m (ud-place! pos (car ks) (add1 col) r)])
             (loop (cdr ks) #f (max last m)))])))

;; ud-layout! places every node and keeps the size of the grid.
(define (ud-layout!)
  (let ([pos (make-hash)])
    (let loop ([rs ud-roots] [row 0])
      (unless (null? rs)
        (loop (cdr rs) (add1 (ud-place! pos (car rs) 0 row)))))
    (set! ud-pos pos)
    (set! ud-rows-count (add1 (for/fold ([m 0]) ([(k v) (in-hash pos)]) (max m (cdr v)))))
    (set! ud-cols-count (add1 (for/fold ([m 0]) ([(k v) (in-hash pos)]) (max m (car v)))))))

;; ud-parent-of answers the parent of a node, or false.
(define (ud-parent-of id)
  (let ([p (ud-node-parent (hash-ref ud-nodes id))])
    (and p (hash-ref ud-nodes p #f) p)))

;; ud-next-of answers the child that forward goes to: the one last used, else the newest.
(define (ud-next-of id)
  (let ([ks (hash-ref ud-kids id (list))] [pref (hash-ref ud-prefer id #f)])
    (cond [(null? ks) #f]
          [(and pref (member pref ks)) pref]
          [else (car (reverse ks))])))

;; ud-newest answers the newest node.
(define (ud-newest) (car (reverse ud-order)))
