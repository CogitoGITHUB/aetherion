//! Conversions between aiu-shell styles and ratatui styles, shared with `aiu-shell-tui`.
//!
//! `explore` and the `tui` commands both draw with ratatui, so the mapping
//! from `$env.config.color_config`, `LS_COLORS`, and ANSI escapes lives here
//! once.

pub use crate::explore::aiu_shell_common::{create_lscolors, get_path_style};
pub use crate::explore::views::colored_text_widget::style_to_tui as ansi_style_to_tui;
pub use crate::explore::views::util::{
    aiu_shell_ansi_color_to_tui_color, aiu_shell_style_to_tui, text_style_to_tui_style,
};
