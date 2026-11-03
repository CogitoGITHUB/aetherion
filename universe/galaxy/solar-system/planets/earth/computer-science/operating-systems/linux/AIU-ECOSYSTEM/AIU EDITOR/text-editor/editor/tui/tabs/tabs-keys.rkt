#lang racket/base
;; tabs-keys.rkt: One job: the keys of the tab layer and its level adjuster, as data.

;; tab-keys are the keys of the tab layer: h and left go to the tab before, t and
;; right to the tab after, o opens the next page of the folder, c closes the tab,
;; p, u and b place the bar, j joins it to the bar, x hides it and v enters the
;; level adjuster.
(define tab-keys
  (list (list "h" "tab-prev")
        (list "t" "tab-next") (list "left" "tab-prev") (list "right" "tab-next")
        (list "o" "tab-open")
        (list "c" "tab-close")
        (list "p" "tab-place-next")
        (list "u" "tab-top")
        (list "b" "tab-bottom")
        (list "j" "tab-join")
        (list "x" "tab-hide")
        (list "v" "tab-level-mode")
        (list "escape" "visual-mode")))

;; tab-level-keys are the keys of the tab level adjuster: h hides one level, t
;; shows one more, and escape goes back to the tab layer.
(define tab-level-keys
  (list (list "h" "tab-less")
        (list "t" "tab-more") (list "left" "tab-less") (list "right" "tab-more")
        (list "escape" "tab-mode")))

(provide tab-keys tab-level-keys)
