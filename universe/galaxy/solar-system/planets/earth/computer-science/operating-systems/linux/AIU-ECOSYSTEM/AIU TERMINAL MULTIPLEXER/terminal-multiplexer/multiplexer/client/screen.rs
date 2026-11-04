
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

const ESCAPE: u8 = 0x1b;
const ENTER: u8 = 0x0d;
const BACKSPACE: u8 = 0x7f;
const RESERVED_PREFIX: u8 = 0x02;
const KEPT: usize = 400;

const RING_KEPT: usize = 20;

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
#[path = "screen_bar/screen_bar_box.rs"]
mod screen_bar_box;
pub(crate) use screen_bar_box::*;
#[path = "screen_bar/screen_bar_rows.rs"]
mod screen_bar_rows;
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
