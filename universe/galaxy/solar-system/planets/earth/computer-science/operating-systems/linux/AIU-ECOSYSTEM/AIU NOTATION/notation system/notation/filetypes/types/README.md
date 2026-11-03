# filetypes/types/

One `.rkt` per file type, or one folder per type. This is where a type is defined.
The starter page of each type is generated into `types/` at the top of the repo. Never edit those by hand.

A page picks a type with `kind: NAME` under its title start line; `check` then rejects any block the type does not allow.

Make a type: copy `default.rkt` to `NAME.rkt`, change the name, the description and the allowed block names (`#f` allows any), then from `notation system/` run:

    racket notation/src/filetypes/make-live.rkt
    nu gate/check.nu

A folder type is `NAME/type.rkt` starting with `(require "../_base.rkt")`. Names starting with an underscore are not types.
