#lang racket/base
;; make-live.rkt -- writes one starter page per file type into types/.
;; Why: a starter page generated from the type cannot drift from the type, and it explains the type in plain words.
;; Called by: a person, from "notation system/": racket notation/src/filetypes/make-live.rkt
(require racket/file
         racket/runtime-path
         racket/string
         "filetypes.rkt")

;; The folder the starter pages are written to.
(define-runtime-path live-dir "../../../../types")

;; The text each type shows. Per type: "title" (a string), "intro" and one entry per section title.
;; An entry is a list; a string in it is a paragraph, a list (code LANGUAGE TEXT) is a code block.
(define texts
  (hash
   "decision"
   (hash "title" "Decision page: record one choice and why"
         "intro" (list "Use a decision page when you choose between options and want the reason to survive. Fill each section below and replace this text with your own.")
         "Context" (list "Say what forces the choice now: the problem, the limits, and what happens if nothing changes. Write it so a stranger understands it a year from now. Keep it short and factual.")
         "Options" (list "List the realistic ways to solve it, one sentence each, and say which you rejected and why. A rejected option written down stops the same argument from coming back.")
         "Decision" (list "State the one choice you made, in a sentence someone can act on. No hedging and no list of maybes.")
         "Consequences" (list "Say what becomes easier, and above all what becomes harder, because of this choice. This is the part you will be glad to have in a year.")
         )
   "plan"
   (hash "title" "Plan page: a goal, the steps, and when it is done"
         "intro" (list "Use a plan page for work that has an end. It forces you to say what finished means, so the plan cannot be silently dropped.")
         "Goal" (list "Write the outcome as one sentence, not an activity. Say what will be true when you are finished, for example a result someone could look at.")
         "Steps" (list "Write each step as one action that can be finished and checked, one paragraph per step."
                       "Put the steps in the order you will do them. If a step needs two actions, split it.")
         "Done when" (list "Write the test that proves the goal is reached, so someone else could run it without asking you.")
         "Open questions" (list "List what you do not know yet, and who can answer each question. Remove a question once it is answered.")
         )
   "research"
   (hash "title" "Research page: a question, how you tested it, what you found"
         "intro" (list "Use a research page when you investigate one question and want a reader to find the method and the results without reading everything. Replace each section text with your own.")
         "Abstract" (list "Summarise the whole page in a few sentences: the question, the method, the result and one limit. Write it last. A reader who stops here should still know what you found.")
         "Introduction" (list "Say what the question is and why it matters. Name what is already known and what is missing, so the reader sees where your work fits.")
         "Methods" (list "Describe what you did so a reader could repeat it from this text alone: the material, the steps and the tools. Put commands or code in a code block.")
         "Results" (list "Report what you found, without opinion. Every claim must point to evidence such as a number, a quote or a file. Leave the meaning for the next section.")
         "Discussion" (list "Say what the results mean, what they do not show, and what to test next. Be honest about limits and about anything that surprised you.")
         "References" (list "List every source you cited, one per line, with enough detail to find it again. A source in the text must appear here.")
         )
   "module"
   (hash "title" "Module page: a piece of code, explained before it is shown"
         "intro" (list "Use a module page to document one piece of code so it can be understood without running it. Say what it is for first, then show it.")
         "Purpose" (list "Say what problem this code solves and what it leaves out. Keep it short. If you cannot state the purpose in a few sentences, the module is doing too much.")
         "Code" (list "The code goes in a code block, with its language written under the start line. Below is a tiny example."
                      (list "code" "racket" "(define (greet name)\n  (string-append \"hello \" name))"))
         )
   "note"
   (hash "title" "Note page: one idea in a few paragraphs"
         "intro" (list "Use a note page to capture one idea. It has a title and paragraphs, and it cannot hold sections, so it stays small. If the idea grows, move it to a bigger page type."
                       "Write the idea so a reader could restate it in one sentence, and keep each paragraph to one point.")
         )
   "journal"
   (hash "title" "Journal page: dated entries in plain prose"
         "intro" (list "Use a journal page to write what happened and what you learned, one section per day or topic. Put the date or the topic in each section title.")
         "First section" (list "Write what happened, what you decided and what you learned, in plain sentences. Do not tidy it. A later reader needs the facts and the reason more than good style.")
         )
   "todo"
   (hash "title" "Todo page: tasks grouped in sections"
         "intro" (list "Use a todo page for tasks. Each task is one short paragraph, and sections group them by theme.")
         "First section" (list "Write one task per paragraph, as one action that can be finished and checked."
                               "Keep it under forty words. If a task needs more, split it into two tasks.")
         )
   "book"
   (hash "title" "Book page: a chapter of sections and prose"
         "intro" (list "Use a book page for long writing: a chapter, a guide or an essay. The title names the chapter and each section covers one part of it.")
         "First section" (list "A section develops one idea over a few paragraphs. Keep each paragraph to a single point a reader could restate, and start a new section when the idea changes.")
         )
   "default"
   (hash "title" "Default page: any block, when no other type fits"
         "intro" (list "The default type allows every block and has no required sections. Use it for pages that do not fit a type, and pick a stricter type when one does.")
         "First section" (list "A section groups blocks under one title. This one holds a paragraph and a code block, with the language written under the start line."
                               (list "code" "racket" "(display \"hello\")"))
         )))

;; title-of finds the title of a type as a string.
(define (title-of type-name)
  (hash-ref (hash-ref texts type-name (hash)) "title" "A new page"))

;; text-of finds the entries of one key of one type, or a plain filler when there are none.
(define (text-of type-name key)
  (hash-ref (hash-ref texts type-name (hash)) key (list "Write here.")))

;; allowed? answers whether a type may use a block name.
(define (allowed? t name)
  (define names (file-type-allowed-blocks t))
  (or (not names) (and (member name names) #t)))

;; block-text writes one block: its start line, its body lines and its end line, then a
;; blank line.
(define (block-text name lines)
  (string-append name " start\n"
                 (apply string-append (map (lambda (l) (string-append l "\n")) lines))
                 name " end\n\n"))

;; section-text writes one section: its title block, then the blocks inside it (already
;; text).
(define (section-text title body)
  (string-append "section start\n"
                 (block-text "title" (list title))
                 body
                 "section end\n\n"))

;; item-text writes one entry: a paragraph for a string, a code block for a code list, and
;; nothing when the type does not allow that block.
(define (item-text t item)
  (cond
    [(string? item) (if (allowed? t "paragraph") (block-text "paragraph" (list item)) "")]
    [(allowed? t "code")
     (block-text "code" (cons (string-append "language: " (cadr item))
                              (string-split (caddr item) "\n" #:trim? #f)))]
    [else ""]))

;; items-text writes a list of entries one after the other.
(define (items-text t items)
  (apply string-append (map (lambda (i) (item-text t i)) items)))

;; sections-for writes the sections of a starter page: one for each title the type requires,
;; one generic section when it requires none, and nothing when sections are not allowed.
(define (sections-for t)
  (define name (file-type-name t))
  (define titles (required-sections-of name))
  (cond
    [(not (allowed? t "section")) ""]
    [(null? titles) (section-text "First section" (items-text t (text-of name "First section")))]
    [else
     (apply string-append
            (for/list ([title (in-list titles)])
              (section-text title (items-text t (text-of name title)))))]))

;; starter-page builds the text of one type starter page from what the type allows.
(define (starter-page t)
  (define name (file-type-name t))
  (string-append
   (block-text "title" (list (string-append "kind: " name)
                             (string-append "tags: " name)
                             (title-of name)))
   (items-text t (text-of name "intro"))
   (sections-for t)
   (if (allowed? t "comment") (block-text "comment" (list (file-type-description t))) "")))

;; blk builds the lines of one block: its start line, its inner lines and its end line.
(define (blk name lines)
  (append (list (string-append name " start")) lines (list (string-append name " end"))))

;; The showcase page for comments attached to blocks and for todo marks.
(define showcase-comment
  (string-join
   (append
    (blk "title" (list "kind: default" "tags: comment todo" "Comments and todo marks on blocks"))
    (list "")
    (blk "paragraph" (list "This page shows two features. A comment can be attached to one block or to several blocks at once. A todo mark puts the word TODO down the left edge of any block."))
    (list "")
    (blk "section"
         (append
          (blk "title" (list "A comment on one block"))
          (list "")
          (blk "paragraph"
               (append (list "Install the tool on a clean machine and run the checker on one page.")
                       (blk "comment" (list "This comment sits inside the paragraph it belongs to. The viewer draws it as its own box inside that block, so you see at once what it is about.")))))) 
    (list "")
    (blk "section"
         (append
          (blk "title" (list "A comment on two blocks"))
          (list "")
          (blk "comment"
               (append
                (list "One comment for both paragraphs below. Write the note first, then put the blocks it covers inside the comment.")
                (list "")
                (blk "paragraph" (list "First block covered by the comment."))
                (list "")
                (blk "paragraph" (list "Second block covered by the same comment."))))))
    (list "")
    (blk "section"
         (append
          (blk "title" (list "A todo mark"))
          (list "")
          (blk "paragraph"
               (append (list "todo: open" "Write the install guide.")
                       (blk "comment" (list "todo: open draws TODO in red down the left side of the block."))))
          (list "")
          (blk "paragraph" (list "todo: done" "Fix the viewer so block names sit on the left.")))))
   "\n"))

;; main writes a starter page for every type that loads.
(module+ main
  (make-directory* live-dir)
  (for ([(name t) (in-hash (load-file-types))])
    (define file (build-path live-dir (string-append name ".aiu")))
    (display-to-file (starter-page t) file #:exists (quote truncate))
    (printf "wrote ~a\n" file))
  (define showcase-file (build-path live-dir "comment.aiu"))
  (display-to-file (string-append showcase-comment "\n") showcase-file #:exists (quote truncate))
  (printf "wrote ~a\n" showcase-file))
