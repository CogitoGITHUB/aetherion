# filetypes/types/

One .rkt per file type, or one folder per type. A type holds its
name, its description and its allowed blocks. Its contracts are not
here: they are files in .notation/TYPE/, one file per contract.

A contract file holds one Racket list, named by its id for a
question, or by its rule for a rule. The nearest .notation/TYPE/
folder up the tree from the page wins. A folder with its own
.notation/ but no folder for a type falls back to the parent.

A page picks a type with kind: NAME under its title start line.
check then rejects any block the type does not allow.

Make a type: copy default.rkt to NAME.rkt, change the name, the
description and the allowed blocks (#f allows any), add its
contract files, then from AIU-ECOSYSTEM run:

    racket "AIU NOTATION/notation/filetypes/make-live.rkt"
    nu gate/check.nu

A folder type is NAME/type.rkt starting with
(require "../_base.rkt"). Names starting with an underscore are
not types.
