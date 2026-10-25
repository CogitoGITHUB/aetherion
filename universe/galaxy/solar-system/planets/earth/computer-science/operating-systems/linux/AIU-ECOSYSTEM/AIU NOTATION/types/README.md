# types/

One module per file type, or one folder per type. A page picks a type with `kind: NAME` under its title's start line; `check` then rejects any block the type does not allow.

Make a type (copy this to `types/NAME.rkt`, change the three marked values):

    #lang racket/base
    ;; NAME.rkt -- the file type "NAME": one line saying what it is for.
    ;; Called by: filetypes.rkt (found by scanning types/).
    (require "_base.rkt")
    (provide the-type)

    ;; The NAME type.
    (define the-type (file-type "NAME" "one line description" (list "title" "paragraph")))

- The last argument is the allowed block names, or `#f` to allow any block.
- A type with more modules is a folder: `types/NAME/type.rkt` starting with `(require "../_base.rkt")`.
- A name starting with an underscore is not a type.
- Every definition needs a comment line above it, and every file a header comment (the gate checks this).
- Test it from `notation system/`: `nu gate/check.nu`.
