#lang racket/base

(define find-keys
  (list (list "f t" "find-file-text")
        (list "f b" "find-file-blocks")
        (list "f d" "find-file-todos")
        (list "p t" "find-project-text")
        (list "p b" "find-project-blocks")
        (list "p d" "find-project-todos")
        (list "p n" "find-project-files")
        (list "w t" "find-workspace-text")
        (list "w b" "find-workspace-blocks")
        (list "w d" "find-workspace-todos")
        (list "w n" "find-workspace-files")
        (list "escape" "visual-mode")))

(provide find-keys)
