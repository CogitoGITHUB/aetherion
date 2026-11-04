#lang racket/base

(require "session-shared.rkt")

(define extra-cursors (box (list)))

(define main-anchor (box #f))

(define multi-raw-view (box #f))

(define multi-file (box #f))

(define multi-lit-hook (box (lambda (got ranges point) (list))))

(define multi-text-hook (box (lambda (raw top visible offset left width layer point) "")))

(define multi-edit-hook (box #f))

(define (multi-live? session)
  (and (equal? (unbox multi-file) (session-file session))
       (or (pair? (unbox extra-cursors)) (and (unbox main-anchor) #t) (unbox multi-raw-view))
       #t))

(define (multi-raw? session)
  (and (unbox multi-raw-view) (equal? (unbox multi-file) (session-file session)) #t))

(define (multi-clear!)
  (set-box! extra-cursors (list))
  (set-box! main-anchor #f)
  (set-box! multi-raw-view #f))

(provide extra-cursors main-anchor multi-raw-view multi-file multi-lit-hook multi-text-hook
         multi-edit-hook multi-live? multi-raw? multi-clear!)

(define (multi-drop-selections!)
  (set-box! main-anchor #f)
  (set-box! extra-cursors (map (lambda (c) (cons (car c) #f)) (unbox extra-cursors)))
  (set-box! multi-raw-view #f))

(provide multi-drop-selections!)
