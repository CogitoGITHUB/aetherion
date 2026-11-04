// One job: the screen — the panes drawn on one terminal, the mode line, the
// tab bar, the keymap explorer, and the redraw when something arrives.
//
// The screen holds nothing: the panes, their shells and their output belong
// to the holder. What lives here is what the owner sees and what the owner
// presses.
//
// The keys are read through the keymap (=keymap.rs=): the same table says
// what the keys do and what the explorer shows, so the two cannot drift
// apart. The modes are Visual (the multiplexer's own keys), Insert (the
// pane's own keys), Command (the command line) and Explorer (the keymap
// explorer).

use serde_json::{json, Value};
use std::io::Write;

use super::clipboard;
use super::keymap::{bindings, Command, Context, Keymap, Mode, Resolution, State};
use super::select::Selection;
use super::tty;
use super::wire;
use super::config::{ConfigFile, Reload};
use super::control;
use super::geometry;

/// ESCAPE leaves Insert, and cancels a sequence or the explorer.
const ESCAPE: u8 = 0x1b;
/// ENTER ends a command line.
const ENTER: u8 = 0x0d;
/// BACKSPACE takes the last character off the command line.
const BACKSPACE: u8 = 0x7f;
/// RESERVED_PREFIX is the escape hatch: the multiplexer keeps it in every
/// mode, so the owner can reach the multiplexer's own keys while a program
/// in the focused pane has the keyboard. Every other key in Insert belongs
/// to that program (rule 06).
const RESERVED_PREFIX: u8 = 0x02;
/// KEPT is how many lines of a pane's output the screen remembers.
const KEPT: usize = 400;

/// RING_KEPT is how many copies the multiplexer's own ring holds. The
/// ring is a small buffer: the newest copy is the first one.
const RING_KEPT: usize = 20;

/// VIEW_LINES is how many lines of a pane the agent's view carries: the
/// newest ones, each with the number the agent names it by.
const VIEW_LINES: usize = 40;

#[path = "screen_state/screen_state_settings.rs"]
mod screen_state_settings;
#[path = "screen_state/screen_state_records.rs"]
mod screen_state_records;
#[path = "screen_focus/screen_focus_lookup.rs"]
mod screen_focus_lookup;
#[path = "screen_paint/screen_paint_frame.rs"]
mod screen_paint_frame;
#[path = "screen_paint/screen_paint_scroll.rs"]
mod screen_paint_scroll;
#[path = "screen_paint/screen_paint_rows.rs"]
mod screen_paint_rows;
#[path = "screen_key/screen_key_input.rs"]
mod screen_key_input;
#[path = "screen_run/screen_run_command.rs"]
mod screen_run_command;
#[path = "screen_take/screen_take_answers.rs"]
mod screen_take_answers;
#[path = "screen_select/screen_select_region.rs"]
mod screen_select_region;
#[path = "screen_select/screen_select_paste.rs"]
mod screen_select_paste;
#[path = "screen_agent/screen_agent_open.rs"]
mod screen_agent_open;
#[path = "screen_control/screen_control_words.rs"]
mod screen_control_words;
#[path = "screen_session/screen_session_switch.rs"]
mod screen_session_switch;
#[path = "screen_pane/screen_pane_move.rs"]
mod screen_pane_move;
#[path = "screen_type/screen_type_structs.rs"]
mod screen_type_structs;
pub(crate) use screen_type_structs::*;
#[path = "screen_type/screen_type_methods.rs"]
mod screen_type_methods;
pub(crate) use screen_type_methods::*;
#[path = "screen_text/screen_text_clip.rs"]
mod screen_text_clip;
pub(crate) use screen_text_clip::*;
#[path = "screen_loop/screen_loop_session.rs"]
mod screen_loop_session;
pub(crate) use screen_loop_session::*;
#[path = "screen_record/screen_record_refusal.rs"]
mod screen_record_refusal;
pub(crate) use screen_record_refusal::*;

#[cfg(test)]
#[path = "screen_test/screen_test_behavior.rs"]
mod tests;
