#lang racket/base
;; One job: the clock of the bar. The time and the date are read at each paint, so no timer runs.

;; day-names are the short names of the days, Sunday first.
(define day-names (vector "Sun" "Mon" "Tue" "Wed" "Thu" "Fri" "Sat"))

;; month-names are the short names of the months.
(define month-names (vector "Jan" "Feb" "Mar" "Apr" "May" "Jun" "Jul" "Aug" "Sep" "Oct" "Nov" "Dec"))

;; two answers a number as two digits.
(define (two n) (if (< n 10) (string-append "0" (number->string n)) (number->string n)))

;; clock-time answers the time as 21:30.
(define (clock-time)
  (define d (seconds->date (current-seconds)))
  (string-append (two (date-hour d)) ":" (two (date-minute d))))

;; clock-date answers the day and the date as Fri 30 Oct.
(define (clock-date)
  (define d (seconds->date (current-seconds)))
  (string-append (vector-ref day-names (date-week-day d)) " " (number->string (date-day d)) " "
                 (vector-ref month-names (sub1 (date-month d)))))

(provide day-names month-names two clock-time clock-date)
