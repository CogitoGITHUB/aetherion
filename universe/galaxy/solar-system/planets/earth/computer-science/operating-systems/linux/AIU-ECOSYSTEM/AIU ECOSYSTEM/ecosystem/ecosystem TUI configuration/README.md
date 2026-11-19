# AIU settings TUI

Full screen terminal editor for the master view settings of the
AIU website. Every change is saved and applied at once.

## Open and hide

It runs as the fifth float of the AIU TERMINAL MULTIPLEXER, named
settings (tab bar: todo journal notes splash settings).

- Open: press e in the shell Visual mode.
- Hide: press e inside the settings screen.
- Show again: press e in the shell Visual mode.

Hiding never kills the program. It keeps running, so the screen
comes back instantly with the same selection. In the shell Insert
mode e types a normal e.

How it works: the shell sends the private signal ESC ] 7704 ; e
BEL to the multiplexer, and the TUI sends the same signal to hide.
The multiplexer toggles the settings float on every signal. The
shell sends it only when AIU_IN_MULTIPLEXER is set.

## Keys

- h       move the selection up
- t       move the selection down
- n       decrease the selected value by its step
- s       increase the selected value by its step
- enter   type a value
- e       hide the float
- ctrl+c  end the TUI process (hiding is enough, avoid it)

The arrow keys also work: up down move, left right change.

Typing a value: press enter, the value shows with an underscore.
Type the new value, backspace deletes, enter commits. There is no
cancel key: delete everything and press enter to leave the value
as it was (status: empty, not changed).

- A number is clamped to the min and max of its row.
- Text in a number row shows the status: not a number.
- The scope row takes any text. n and s toggle it between all
  and its default demo/.

## Screen

Title line, five boxes (cards, arrows, spacing, text, scope), a
help line and a status line. Each row shows a pointer on the
selected row, the label, a 10 cell bar filled by the position of
the value in its range, the value and a short description.
Width follows the window, between 44 and 78 columns. Redraws start
at the top and clear only the line ends, so there is no flicker.
Colors come only from the theme engine (theme.rkt, classes text,
dim and error), read again on every draw.

## Settings

Format: key, range, step, default, meaning.

cards
- width      120-480  step 8    default 240  card width
- height     40-240   step 4    default 76   card height

arrows
- curve      0.05-1   step 0.05 default 0.5  where arrows bend

spacing
- gap        4-100    step 2    default 24   space between boxes
- stepx      120-600  step 8    default 264  column distance
- stepy      40-300   step 4    default 100  row distance
- margin     10-600   step 10   default 200  free space around
- pad        4-60     step 2    default 16   space inside a box
- head       20-140   step 2    default 56   box title height

text
- padv       1-40     step 1    default 10   card padding top
- padh       1-40     step 1    default 12   card padding side
- titlesize  8-40     step 1    default 15   card title font
- descsize   8-30     step 1    default 12   description font
- labelsize  8-30     step 1    default 13   box label font

scope
- scope      text     default demo/  folder shown, or all

A key missing from the file starts at its default.

## How a change is applied

1. The value changes in memory (n, s or typed).
2. The file is rewritten: AIU NOTATION/notation/layouts/
   layout-settings.aiu. Known keys are replaced in place. Keys
   missing from the file are added just before the line
   settings end. Every other line stays as it is.
3. A background thread sends POST reload to the ecosystem server
   at http://127.0.0.1:8080/cmd. Keys never wait for the server.
   If the server is not running the file is still saved, and the
   status line says saved either way.
4. The server indexes the settings block and the website loads
   the values (set_cfg in website/lib.rs), so the master view
   follows without a manual refresh.

## Files

- ecosystem TUI configuration/settings-tui.rkt   the program
- ecosystem TUI configuration/settings-pane.sh   launcher
- AIU NOTATION/notation/layouts/layout-settings.aiu   the values
- AIU TERMINAL MULTIPLEXER/multiplexer/entry/mux.rkt   float
- AIU TERMINAL MULTIPLEXER/multiplexer/pane/pane-grid.rkt   signal
- aiu-shell/.../aiu-shell-screen/src/input_state.rs   key e
- aiu-shell/.../aiu-shell-screen/src/command_runner.rs
  toggle_settings, sends the signal

The launcher reads the root folder from the state file
~/.local/state/aiu-ecosystem/root, changes into it, sets LANG,
LC_ALL and PLTCOMPILEDROOTS and runs the program with
~/opt/racket-full/bin/racket.

## Run by hand and check

Run from the AIU-ECOSYSTEM folder with the same environment as
the launcher, and give the program as the file argument:

    racket "AIU ECOSYSTEM/ecosystem/ecosystem TUI configuration/settings-tui.rkt" check

check loads the file and prints ok and the number of keys (15).
Without a real terminal the program prints: needs a real
terminal. Outside the AIU-ECOSYSTEM folder it prints: run from
the AIU-ECOSYSTEM folder, settings file not found.

## Add a setting

1. Add a row to the rows list in settings-tui.rkt: key, label,
   min, max, step, default, description. Use #f for min and max
   to make a text row.
2. Add the key to one of the groups in the same file.
3. Make the website read the key (set_cfg in website/lib.rs).

The TUI itself needs no other change: save writes any known key.

## Notes

- The settings TUI and the multiplexer are Racket: edits load
  after a restart of the multiplexer. The shell part is Rust and
  needs a live build (ecosystem live aiu-shell).
- In the shell Visual mode e used to move between boxes of one
  kind. It now opens and hides the settings.
- Theme rule: this program never configures a theme. It only
  reads the theme engine.
