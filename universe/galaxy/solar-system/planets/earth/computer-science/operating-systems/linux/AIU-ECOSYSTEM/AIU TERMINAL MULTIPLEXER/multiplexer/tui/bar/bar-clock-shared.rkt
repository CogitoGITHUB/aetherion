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

(define (clock-day-part hour)
  (cond [(< hour 6) "Night"]
        [(< hour 12) "Morning"]
        [(< hour 14) "Midday"]
        [(< hour 18) "Afternoon"]
        [else "Evening"]))

(define (clock-join parts)
  (let loop ([rest parts] [out ""])
    (cond [(null? rest) out]
          [(not (car rest)) (loop (cdr rest) out)]
          [(string=? out "") (loop (cdr rest) (car rest))]
          [else (loop (cdr rest) (string-append out "  " (car rest)))])))

(define (clock-stamp room time? date?)
  (define d (seconds->date (current-seconds)))
  (define hour (date-hour d))
  (define hm (string-append (two hour) ":" (two (date-minute d))))
  (define hms (string-append hm ":" (two (date-second d))))
  (define ymd (string-append (number->string (date-year d)) "-" (two (date-month d)) "-" (two (date-day d))))
  (define part (clock-day-part hour))
  (define weekday (vector-ref day-names (date-week-day d)))
  (define variants
    (list (clock-join (list (and time? part) (and time? hms) (and date? (string-append ymd " " weekday))))
          (clock-join (list (and time? part) (and time? hms) (and date? ymd)))
          (clock-join (list (and time? hms) (and date? ymd)))
          (clock-join (list (and time? hm) (and date? ymd)))
          (clock-join (list (and time? hm)))
          ""))
  (let loop ([rest variants])
    (cond [(null? rest) ""]
          [(<= (string-length (car rest)) room) (car rest)]
          [else (loop (cdr rest))])))

(define (clock-rule-line l r width time? date?)
  (define gap 4)
  (define text (clock-stamp (- width 10) time? date?))
  (if (string=? text "")
      (string-append l (make-string (max 0 (- width 2)) #\─) r)
      (let ([used (+ 4 (string-length text) gap)])
        (string-append l (make-string (max 0 (- width 2 used)) #\─) "┤ " text " ├" (make-string gap #\─) r))))

(provide day-names month-names two clock-time clock-date clock-stamp clock-rule-line)
