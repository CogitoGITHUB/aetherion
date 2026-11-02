#lang racket/base
;; One job: the state boxes of the cursors and the selections - the extra
;; cursors, the anchor of the point, the raw view flag, the hooks that
;; multi.rkt fills, and the questions and resets over them. It requires no
;; command: commands.rkt requires this file and passes every name on.

(require "session.rkt")

;; extra-cursors holds the cursors besides the point, each as (head . anchor); the anchor is false when that
;; cursor selects nothing. There is no limit on how many there are.
(define extra-cursors (box (list)))

;; main-anchor is where the selection of the point began, or false.
(define main-anchor (box #f))

;; multi-raw-view is true while the select layer shows the raw text instead of the drawn page.
(define multi-raw-view (box #f))

;; multi-file is the file the cursors and the selections above belong to.
(define multi-file (box #f))

;; multi-lit-hook answers the line ranges the cursors and selections light in the drawn page; multi.rkt sets it.
(define multi-lit-hook (box (lambda (got ranges point) (list))))

;; multi-text-hook answers the escape text that draws cursors and selections over the raw text; multi.rkt sets it.
(define multi-text-hook (box (lambda (raw top visible offset left width layer point) "")))

;; multi-edit-hook runs an edit or a move for every cursor; multi.rkt sets it.
(define multi-edit-hook (box #f))

;; multi-live? asks whether the cursors and the selections of this session are in use.
(define (multi-live? session)
  (and (equal? (unbox multi-file) (session-file session))
       (or (pair? (unbox extra-cursors)) (and (unbox main-anchor) #t) (unbox multi-raw-view))
       #t))

;; multi-raw? asks whether the raw text is shown for the selection of this session.
(define (multi-raw? session)
  (and (unbox multi-raw-view) (equal? (unbox multi-file) (session-file session)) #t))

;; multi-clear! drops every extra cursor and every selection.
(define (multi-clear!)
  (set-box! extra-cursors (list))
  (set-box! main-anchor #f)
  (set-box! multi-raw-view #f))

(provide extra-cursors main-anchor multi-raw-view multi-file multi-lit-hook multi-text-hook
         multi-edit-hook multi-live? multi-raw? multi-clear!)

;; multi-drop-selections! takes every selection away and keeps the extra cursors.
(define (multi-drop-selections!)
  (set-box! main-anchor #f)
  (set-box! extra-cursors (map (lambda (c) (cons (car c) #f)) (unbox extra-cursors)))
  (set-box! multi-raw-view #f))

(provide multi-drop-selections!)
