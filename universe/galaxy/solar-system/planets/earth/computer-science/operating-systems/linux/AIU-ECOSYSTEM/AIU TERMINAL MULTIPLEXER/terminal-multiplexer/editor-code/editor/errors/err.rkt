#lang racket/base

(struct err (kind who where what what-to-do) #:transparent)

(struct exn:fail:editor exn:fail (err) #:transparent)

(provide err
         exn:fail:editor
         exn:fail:editor?
         exn:fail:editor-err
         err-kind
         err-who
         err-where
         err-what
         err-what-to-do)
