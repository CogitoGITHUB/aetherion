#lang racket/base

(define day-names (vector "Sun" "Mon" "Tue" "Wed" "Thu" "Fri" "Sat"))

(define month-names (vector "Jan" "Feb" "Mar" "Apr" "May" "Jun" "Jul" "Aug" "Sep" "Oct" "Nov" "Dec"))

(define (two n) (if (< n 10) (string-append "0" (number->string n)) (number->string n)))

(define (clock-time)
  (define d (seconds->date (current-seconds)))
  (string-append (two (date-hour d)) ":" (two (date-minute d))))

(define (clock-date)
  (define d (seconds->date (current-seconds)))
  (string-append (vector-ref day-names (date-week-day d)) " " (number->string (date-day d)) " "
                 (vector-ref month-names (sub1 (date-month d)))))

(provide day-names month-names two clock-time clock-date)
