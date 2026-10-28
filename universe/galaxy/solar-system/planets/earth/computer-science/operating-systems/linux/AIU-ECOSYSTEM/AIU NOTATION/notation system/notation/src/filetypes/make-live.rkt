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
(define (starter-page-plain t)
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
               (append (list "todo: write the install guide and test it on a clean machine before Friday" "Install the tool on a clean machine and run the checker on one page.")
                       (blk "comment" (list "The word todo, a colon and a description under the start line puts TODO in the top-right corner and hangs the description under the box. Start the description with done when the task is finished."))))
          (list "")
          (blk "paragraph" (list "todo: done viewer fixed, names now sit on the left" "Fix the viewer so block names sit on the left.")))))
   "\n"))

;; stack joins blocks (each a list of lines) with one blank line between them.
(define (stack . bs)
  (apply append (car bs) (for/list ([b (in-list (cdr bs))]) (cons "" b))))

;; The hand-written todo starter page: marks, comments on one and on two blocks, and an answer.
(define todo-page
  (string-append
   (string-join
    (stack
     (blk "title" (list "kind: todo" "tags: todo viewer" "Todo page: tasks with marks, notes and answers"))
     (blk "paragraph" (list "Use a todo page for tasks. Each task is one short paragraph. A todo line under its start line marks it open or done, and sections group tasks by theme."))
     (blk "section"
          (stack
           (blk "title" (list "Open tasks"))
           (blk "paragraph"
                (append (list "todo: write the install guide and test it on a clean machine before Friday"
                              "Install the tool on a clean machine and run the checker on one page.")
                        (blk "answer" (list "for: qadd5fe"
                                            "asked: Is this one action that can be finished and checked?"
                                            "Yes. One install and one check, finished when the checker prints clean."))))
           (blk "paragraph"
                (append (list "todo: waiting for Anna to name the second operating system"
                              "Test the install on a second operating system.")
                        (blk "comment" (list "Anna may have a spare laptop. Ask her again on Monday. A comment inside a block belongs to that block.")))))) 
     (blk "section"
          (stack
           (blk "title" (list "Done"))
           (blk "comment"
                (append (list "These two tasks came from the same review, so one comment covers both. Put the blocks inside the comment.")
                        (list "")
                        (blk "paragraph" (list "todo: done viewer fixed, block names now sit on the left" "Move the block names to the left edge."))
                        (list "")
                        (blk "paragraph" (list "todo: done contracts now show on every page" "Show the contracts without a flag."))))))
     (blk "section"
          (stack
           (blk "title" (list "Ideas"))
           (blk "paragraph" (list "A task with no todo line is just a note. Keep each task under forty words, and split it when it needs more."))
           (blk "comment" (list "The questions under each block come from the todo type. Fill them in with an answer block; the answer is matched to its question by ID, so reordering questions never breaks it.")))))
    "\n")
   "\n"))

;; ans builds an answer block for the question of a type whose text holds frag, with its ID and saved text.
(define (ans type frag text)
  (define c
    (for/first ([c (in-list (contracts-of type))]
                #:when (and (equal? (symbol->string (car c)) "question")
                            (string-contains? (cadddr c) frag)))
      c))
  (if c
      (blk "answer" (list (string-append "for: " (list-ref c 4))
                          (string-append "asked: " (cadddr c))
                          text))
      (list)))

;; para builds a paragraph from strings (lines) and lists (nested blocks), in the order given.
(define (para . parts)
  (blk "paragraph" (apply append (map (lambda (x) (if (string? x) (list x) x)) parts))))

;; sec builds a section from its title and the blocks inside it.
(define (sec title . kids)
  (blk "section" (apply stack (cons (blk "title" (list title)) kids))))

;; note builds a comment from lines of text.
(define (note . lines)
  (blk "comment" lines))

;; cover builds one comment that wraps several blocks after its own text.
(define (cover text . kids)
  (blk "comment" (apply append (list text) (map (lambda (k) (cons "" k)) kids))))

;; ttl builds the file title block with its kind and tags.
(define (ttl kind tags text)
  (blk "title" (list (string-append "kind: " kind) (string-append "tags: " tags) text)))

;; page joins blocks into the text of a whole page.
(define (page . bs)
  (string-append (string-join (apply stack bs) "\n") "\n"))

;; The decision starter page.
(define (decision-page)
  (page
   (ttl "decision" "decision notes" "Decision page: keep every note as a plain text file")
   (para "Use a decision page when you choose between options and want the reason to survive. This one is a worked example, so replace its text with your own.")
   (sec "Context"
        (para "Notes were spread over three apps, each with its own format. Searching meant opening every app, and an export could lose structure."
              (ans "decision" "What forces" "Searching and exporting were already failing, and the pile grows every week."))
        (note "Keep the context short and factual. A stranger should understand it a year from now."))
   (sec "Options"
        (para "Stay with the three apps. Move everything to one plain text format. Use a database."
              (ans "decision" "Which option was rejected" "The database was rejected, because no plain editor opens it and grep cannot read it."))
        (para "todo: ask whether pictures need a fourth option" "Pictures and tables fit none of these options yet."))
   (sec "Decision"
        (para "Write every note as a plain text file in one folder, and read it with any editor."
              (ans "decision" "Is it one choice" "Yes. One folder and one format, with no exceptions.")))
   (sec "Consequences"
        (para "Search and diffs become simple and nothing is locked in. Pictures and tables need their own answer later."
              (ans "decision" "What gets harder" "Pictures and tables, and any tool that expects a database."))
        (para "todo: done folder created and the first fifty notes moved" "The move started the same week."))))

;; The plan starter page.
(define (plan-page)
  (page
   (ttl "plan" "plan release" "Plan page: ship the first public release")
   (para "Use a plan page for work that has an end. It forces you to say what finished means, so the plan cannot be silently dropped.")
   (sec "Goal"
        (para "A person can install the tool on a clean machine and check one page in under five minutes."
              (ans "plan" "Can the goal" "Yes. One outcome that someone can time.")))
   (sec "Steps"
        (para "todo: done guide written" "Write the install guide in plain steps."
              (ans "plan" "Is each step" "Yes. One action, finished when the guide exists."))
        (para "todo: waiting for a clean machine" "Run the guide on a clean machine and note every place it fails.")
        (para "Fix what the clean run showed, then run it again.")
        (note "A comment inside a block belongs to that block. Use it for a reminder that is not part of the step."))
   (sec "Done when"
        (para "The guide works on a clean machine without help, and the archive is public."
              (ans "plan" "Could someone check" "Yes. Run the guide, then open the public link.")))
   (sec "Open questions"
        (para "todo: ask Anna by Monday" "Who tests on a second operating system, and by what date?"
              (ans "plan" "Who can answer" "Anna, and nobody else has a second machine.")))))

;; The research starter page.
(define (research-page)
  (page
   (ttl "research" "research notes" "Research page: does plain text make notes easier to find")
   (para "Use a research page when you investigate one question and want a reader to find the method and the results at once.")
   (sec "Abstract"
        (para "We ask whether plain text files help a person find an old note faster than a note app does. Twenty notes were searched by hand and by grep on one machine. Grep found every note and the app missed some. The test was small and used one person."
              (ans "research" "Does it state" "Yes. It names the question, the method, the result and one limit.")))
   (sec "Introduction"
        (para "People keep notes for years and then cannot find them. If the storage format decides how fast a note is found, choosing it well saves time every day."
              (ans "research" "why the question matters" "Yes. The cost is paid every day, for years.")))
   (sec "Methods"
        (para "The same twenty notes were stored twice, as text files and in an app. For each note a search phrase was written first, then both stores were searched with it."
              (ans "research" "Could a reader repeat" "Yes, with the phrase list and the command below."))
        (blk "code" (list "language: bash" "grep -rl meeting notes/"))
        (note "A command goes in a code block so a reader can copy it. Always write the language under the start line."))
   (sec "Results"
        (para "Grep returned all twenty notes. The app returned seventeen and ranked four of them below the first page."
              (ans "research" "Does every claim" "Yes. Each count comes from the search log.")))
   (sec "Discussion"
        (para "Plain text looks better for finding notes, but one person and twenty notes show little. A larger test with several people is needed."
              (ans "research" "do these results not show" "They do not show how it scales, or whether other people would find the same."))
        (para "todo: find three people to repeat the test" "A repeat with other people would settle the limit above."))
   (sec "References"
        (para "No sources are cited yet. List each source here as one line."
              (ans "research" "Does every source" "Not yet. The list is empty because the text cites nothing.")))))

;; The module starter page.
(define (module-page)
  (page
   (ttl "module" "module example" "Module page: a tiny function explained before its code")
   (para "Use a module page to document one piece of code so it can be understood without running it. Say what it is for first, then show it.")
   (sec "Purpose"
        (para "Add one to a number. It does not read input, print anything or check that the input is a number."
              (ans "module" "What problem" "It gives the other code one named step for adding one, and nothing more."))
        (para "todo: decide whether it should refuse a text input" "The page leaves that out on purpose."))
   (sec "Code"
        (para "The code goes in a code block, with its language written under the start line.")
        (blk "code" (list "language: racket" "(define (add-one n)" "  (+ n 1))"))
        (note "A code body is opaque, so a question about code cannot be answered inside it. A person answers it here, beside the code."))))

;; The note starter page.
(define (note-page)
  (page
   (ttl "note" "note idea" "Note page: one idea, said once")
   (para "Use a note page to capture one idea. It holds a title and paragraphs only, so it stays small. When the idea grows, move it to a type that has sections."
         (ans "note" "Is this one idea" "Yes. One idea: a note stays small because it cannot grow sections."))
   (para "todo: link this idea to the page that uses it" "Keep each paragraph to one point a reader could restate in a sentence.")
   (note "A note may hold a comment and a code block as well. Here is a code block.")
   (blk "code" (list "language: text" "one idea, a few paragraphs, no sections"))))

;; The journal starter page.
(define (journal-page)
  (page
   (ttl "journal" "journal workshop" "Journal page: a week in the workshop")
   (sec "Monday: the viewer day"
        (para "Moved the block names to the left so the centre is free for the text. Then fixed the todo mark, so the word sits in the wall of the box. Next I want the contracts visible on every page."
              (ans "journal" "What happened" "The viewer changed. I decided to keep the letters in the wall and hang the description under the box.")))
   (sec "Tuesday: contracts and answers"
        (para "todo: write the other starter pages" "Questions now have permanent IDs, so an answer can never end up under the wrong question. Reordering questions no longer breaks a file."
              (ans "journal" "What happened" "Answers match by ID. I learned that the checker was counting nested lines, and fixed it.")))))

;; The book starter page.
(define (book-page)
  (page
   (ttl "book" "book chapter" "Book page: a chapter on how notes become pages")
   (para "Use a book page for long writing: a chapter, a guide or an essay. The title names the chapter and each section covers one part of it.")
   (sec "The idea"
        (para "A note is only useful when it can be found and understood later. A named block tells a reader and a script what each piece of text is."
              (ans "book" "Does this paragraph hold one idea" "Yes. Named blocks make a note findable and readable."))
        (note "A comment can sit in a block, or wrap several blocks as in the next section."))
   (sec "The method"
        (cover "These two paragraphs describe one method, so one comment covers both."
               (para "Write the page, then run the checker until it prints clean.")
               (para "todo: add a short example page" "Read the checker output from the top, because later errors often disappear."))
        (blk "code" (list "language: bash" "aiu check page.aiu")))))

;; The default starter page.
(define (default-page)
  (page
   (ttl "default" "default example" "Default page: every block in one place")
   (para "The default type allows every block and has no required sections. Use it when no other type fits, and pick a stricter type when one does.")
   (sec "Blocks"
        (para "A section groups blocks under one title. This one shows a paragraph, a comment, a code block and a todo mark."
              (ans "default" "Does the paragraph make one point" "Yes. It lists what a section can hold."))
        (para "todo: done add a section inside a section" "Sections nest, so a part can have parts of its own.")
        (blk "code" (list "language: racket" "(display hello)"))
        (note "The default type asks that every code block names its language."))
   (sec "Nested"
        (sec "A section inside a section"
             (para "A section can hold sections, and the viewer numbers them for you.")))))

;; starter-page uses a hand-written page for each type that has one and the generated one for the rest.
(define (starter-page t)
  (define name (file-type-name t))
  (cond
    [(equal? name "todo") todo-page]
    [(equal? name "decision") (decision-page)]
    [(equal? name "plan") (plan-page)]
    [(equal? name "research") (research-page)]
    [(equal? name "module") (module-page)]
    [(equal? name "note") (note-page)]
    [(equal? name "journal") (journal-page)]
    [(equal? name "book") (book-page)]
    [(equal? name "default") (default-page)]
    [else (starter-page-plain t)]))

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
