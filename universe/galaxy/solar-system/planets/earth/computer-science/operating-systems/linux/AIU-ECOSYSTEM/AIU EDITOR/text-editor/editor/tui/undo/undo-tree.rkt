#lang racket/base

(require "undo-git.rkt" (only-in racket/string string-split))

(provide (struct-out undo-node) undo-nodes undo-kids undo-roots undo-order undo-pos undo-rows-count undo-cols-count undo-prefer undo-texts
         undo-older? undo-load-tree! undo-place! undo-layout! undo-parent-of undo-next-of undo-newest)

(struct undo-node (id parent time subject))
(define undo-nodes (make-hash))
(define undo-kids (make-hash))
(define undo-roots (list))
(define undo-order (list))
(define undo-pos (make-hash))
(define undo-rows-count 1)
(define undo-cols-count 1)
(define undo-prefer (make-hash))
(define undo-texts (make-hash))

(define (undo-older? a b)
  (let ([ta (undo-node-time (hash-ref undo-nodes a))] [tb (undo-node-time (hash-ref undo-nodes b))])
    (if (= ta tb) (string<? a b) (< ta tb))))

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

(define (undo-place! pos id col row)
  (hash-set! pos id (cons col row))
  (let loop ([ks (hash-ref undo-kids id (list))] [first? #t] [last row])
    (cond [(null? ks) last]
          [else
           (let* ([r (if first? row (add1 last))]
                  [m (undo-place! pos (car ks) (add1 col) r)])
             (loop (cdr ks) #f (max last m)))])))

(define (undo-layout!)
  (let ([pos (make-hash)])
    (let loop ([rs undo-roots] [row 0])
      (unless (null? rs)
        (loop (cdr rs) (add1 (undo-place! pos (car rs) 0 row)))))
    (set! undo-pos pos)
    (set! undo-rows-count (add1 (for/fold ([m 0]) ([(k v) (in-hash pos)]) (max m (cdr v)))))
    (set! undo-cols-count (add1 (for/fold ([m 0]) ([(k v) (in-hash pos)]) (max m (car v)))))))

(define (undo-parent-of id)
  (let ([p (undo-node-parent (hash-ref undo-nodes id))])
    (and p (hash-ref undo-nodes p #f) p)))

(define (undo-next-of id)
  (let ([ks (hash-ref undo-kids id (list))] [pref (hash-ref undo-prefer id #f)])
    (cond [(null? ks) #f]
          [(and pref (member pref ks)) pref]
          [else (car (reverse ks))])))

(define (undo-newest) (car (reverse undo-order)))
