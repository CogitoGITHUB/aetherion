#lang racket/base
(require racket/list)
(provide (struct-out layout-tab) (struct-out layout-strip) (struct-out layout-state) (struct-out layout-rect)
         layout-new layout-split layout-close layout-focus layout-move layout-cycle-size layout-set-direction
         layout-tab-ids layout-focused-id layout-rects layout-size-presets)

(struct layout-tab (id) #:transparent)
(struct layout-strip (axis items sizes) #:transparent)
(struct layout-state (root focus direction) #:transparent)
(struct layout-rect (id x y width height cut-x cut-y full-width full-height) #:transparent)

(define layout-size-presets (list 1/3 1/2 2/3 1))

(define (layout-new id) (layout-state (layout-tab id) null (quote right)))

(define (direction-axis direction)
  (if (memq direction (quote (left right))) (quote horizontal) (quote vertical)))

(define (direction-after? direction)
  (and (memq direction (quote (right down))) #t))

(define (node-at node path)
  (if (null? path)
      node
      (node-at (list-ref (layout-strip-items node) (car path)) (cdr path))))

(define (node-replace node path replacement)
  (if (null? path)
      replacement
      (let ([items (layout-strip-items node)] [index (car path)])
        (layout-strip (layout-strip-axis node)
                      (list-set items index (node-replace (list-ref items index) (cdr path) replacement))
                      (layout-strip-sizes node)))))

(define (list-insert items index value)
  (append (take items index) (list value) (drop items index)))

(define (list-remove items index)
  (append (take items index) (drop items (add1 index))))

(define (path-descend root path edge)
  (define node (node-at root path))
  (if (layout-tab? node)
      path
      (path-descend root
                    (append path (list (if (eq? edge (quote first)) 0 (sub1 (length (layout-strip-items node))))))
                    edge)))

(define (layout-split state new-id direction)
  (define root (layout-state-root state))
  (define focus (layout-state-focus state))
  (define keep (layout-state-direction state))
  (define axis (direction-axis direction))
  (define after? (direction-after? direction))
  (define fresh (layout-tab new-id))
  (define new-index (if after? 1 0))
  (define (wrap old)
    (layout-strip axis (if after? (list old fresh) (list fresh old)) (list 1/2 1/2)))
  (cond
    [(null? focus) (layout-state (wrap root) (list new-index) keep)]
    [else
     (define parent-path (drop-right focus 1))
     (define index (last focus))
     (define parent (node-at root parent-path))
     (cond
       [(eq? axis (layout-strip-axis parent))
        (define half (/ (list-ref (layout-strip-sizes parent) index) 2))
        (define at (if after? (add1 index) index))
        (define sizes (list-insert (list-set (layout-strip-sizes parent) index half) at half))
        (define items (list-insert (layout-strip-items parent) at fresh))
        (layout-state (node-replace root parent-path (layout-strip axis items sizes))
                      (append parent-path (list at))
                      keep)]
       [else
        (define old (list-ref (layout-strip-items parent) index))
        (layout-state (node-replace root focus (wrap old))
                      (append focus (list new-index))
                      keep)])]))

(define (layout-close state)
  (define root (layout-state-root state))
  (define focus (layout-state-focus state))
  (cond
    [(null? focus) state]
    [else
     (define parent-path (drop-right focus 1))
     (define index (last focus))
     (define parent (node-at root parent-path))
     (define items (layout-strip-items parent))
     (define sizes (layout-strip-sizes parent))
     (define neighbor (if (> index 0) (sub1 index) 1))
     (define gained (+ (list-ref sizes neighbor) (list-ref sizes index)))
     (define remaining-items (list-remove items index))
     (define remaining-sizes (list-remove (list-set sizes neighbor gained) index))
     (define collapsed? (null? (cdr remaining-items)))
     (define rebuilt
       (if collapsed?
           (car remaining-items)
           (layout-strip (layout-strip-axis parent) remaining-items remaining-sizes)))
     (define new-root (node-replace root parent-path rebuilt))
     (define neighbor-path
       (if collapsed? parent-path (append parent-path (list (if (> index 0) (sub1 index) 0)))))
     (layout-state new-root
                   (path-descend new-root neighbor-path (if (> index 0) (quote last) (quote first)))
                   (layout-state-direction state))]))

(define (layout-focus state direction)
  (define root (layout-state-root state))
  (define focus (layout-state-focus state))
  (define axis (direction-axis direction))
  (define step (if (direction-after? direction) 1 -1))
  (let loop ([depth (sub1 (length focus))])
    (cond
      [(< depth 0) state]
      [else
       (define parent-path (take focus depth))
       (define parent (node-at root parent-path))
       (define target (+ (list-ref focus depth) step))
       (if (and (eq? axis (layout-strip-axis parent)) (>= target 0) (< target (length (layout-strip-items parent))))
           (layout-state root
                         (path-descend root (append parent-path (list target)) (if (= step 1) (quote first) (quote last)))
                         (layout-state-direction state))
           (loop (sub1 depth)))])))

(define (layout-move state direction)
  (define root (layout-state-root state))
  (define focus (layout-state-focus state))
  (define axis (direction-axis direction))
  (define step (if (direction-after? direction) 1 -1))
  (cond
    [(null? focus) state]
    [else
     (define parent-path (drop-right focus 1))
     (define parent (node-at root parent-path))
     (define index (last focus))
     (define target (+ index step))
     (cond
       [(and (eq? axis (layout-strip-axis parent)) (>= target 0) (< target (length (layout-strip-items parent))))
        (define (swapped items) (list-set (list-set items index (list-ref items target)) target (list-ref items index)))
        (layout-state (node-replace root parent-path
                                    (layout-strip (layout-strip-axis parent)
                                                  (swapped (layout-strip-items parent))
                                                  (swapped (layout-strip-sizes parent))))
                      (append parent-path (list target))
                      (layout-state-direction state))]
       [else state])]))

(define (layout-cycle-size state)
  (define root (layout-state-root state))
  (define focus (layout-state-focus state))
  (cond
    [(null? focus) state]
    [else
     (define parent-path (drop-right focus 1))
     (define parent (node-at root parent-path))
     (define index (last focus))
     (define size (list-ref (layout-strip-sizes parent) index))
     (define next (or (for/first ([preset (in-list layout-size-presets)] #:when (> preset size)) preset)
                      (car layout-size-presets)))
     (layout-state (node-replace root parent-path
                                 (layout-strip (layout-strip-axis parent)
                                               (layout-strip-items parent)
                                               (list-set (layout-strip-sizes parent) index next)))
                   focus
                   (layout-state-direction state))]))

(define (layout-set-direction state direction)
  (layout-state (layout-state-root state) (layout-state-focus state) direction))

(define (layout-tab-ids state)
  (let loop ([node (layout-state-root state)])
    (if (layout-tab? node)
        (list (layout-tab-id node))
        (append-map loop (layout-strip-items node)))))

(define (layout-focused-id state)
  (layout-tab-id (node-at (layout-state-root state) (layout-state-focus state))))

(define (strip-edges sizes along)
  (let loop ([rest sizes] [cumulative 0] [edges (list 0)])
    (if (null? rest)
        (reverse edges)
        (let ([next (+ cumulative (car rest))])
          (loop (cdr rest) next (cons (round (* along next)) edges))))))

(define (strip-offset edges along total focus-index)
  (cond
    [(or (<= total along) (not focus-index)) 0]
    [else
     (define centre (quotient (+ (list-ref edges focus-index) (list-ref edges (add1 focus-index))) 2))
     (max 0 (min (- total along) (- centre (quotient along 2))))]))

(define (place-node node focus x y width height)
  (cond
    [(layout-tab? node) (list (list (layout-tab-id node) x y width height))]
    [else
     (define horizontal? (eq? (layout-strip-axis node) (quote horizontal)))
     (define along (if horizontal? width height))
     (define edges (strip-edges (layout-strip-sizes node) along))
     (define focus-index (and (pair? focus) (car focus)))
     (define offset (strip-offset edges along (last edges) focus-index))
     (append*
      (for/list ([item (in-list (layout-strip-items node))] [index (in-naturals)])
        (define start (- (list-ref edges index) offset))
        (define extent (- (list-ref edges (add1 index)) (list-ref edges index)))
        (define child-focus (if (and focus-index (= index focus-index)) (cdr focus) null))
        (if horizontal?
            (place-node item child-focus (+ x start) y extent height)
            (place-node item child-focus x (+ y start) width extent))))]))

(define (clip-rect full width height)
  (define-values (id x y w h) (apply values full))
  (define left (max x 0))
  (define top (max y 0))
  (define right (min (+ x w) width))
  (define bottom (min (+ y h) height))
  (and (> right left) (> bottom top)
       (layout-rect id left top (- right left) (- bottom top) (- left x) (- top y) w h)))

(define (layout-rects state width height)
  (filter-map (lambda (full) (clip-rect full width height))
              (place-node (layout-state-root state) (layout-state-focus state) 0 0 width height)))
