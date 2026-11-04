// One job: the keymap — the keys that mean what, as data.
//
// The commands and the keymap explorer read this one table. What the keys do
// and what the explorer shows are the same facts, so they cannot drift apart
// (rule 03: one file, one job; rule 07: the program never learns which key
// asked).
//
// There is no modifier in here: no Control, no Alt, no Meta, and no prefix
// chord. The keys are the ordinary keys of the keyboard, and the sequences
// are ordinary keys one after another. A Control key that the owner presses
// belongs to the program in the pane, not to the multiplexer — the one
// exception is the reserved prefix, and that one is the client's, not this
// table's (D-027).

#[path = "keymap_table/keymap_table_root.rs"]
mod keymap_table_root;
pub use keymap_table_root::ROOT;
#[path = "keymap_table/keymap_table_workspace.rs"]
mod keymap_table_workspace;
pub use keymap_table_workspace::WORKSPACE;
#[path = "keymap_table/keymap_table_select.rs"]
mod keymap_table_select;
pub use keymap_table_select::SELECT;
#[path = "keymap_table/keymap_table_git.rs"]
mod keymap_table_git;
pub use keymap_table_git::GIT;
#[path = "keymap_table/keymap_table_tabs.rs"]
mod keymap_table_tabs;
pub use keymap_table_tabs::TABS;
#[path = "keymap_table/keymap_table_panes.rs"]
mod keymap_table_panes;
pub use keymap_table_panes::PANES;
#[path = "keymap_table/keymap_table_commands.rs"]
mod keymap_table_commands;
pub use keymap_table_commands::COMMANDS;
#[path = "keymap_table/keymap_table_sessions.rs"]
mod keymap_table_sessions;
pub use keymap_table_sessions::SESSIONS;
#[path = "keymap_type/keymap_type_context.rs"]
mod keymap_type_context;
pub(crate) use keymap_type_context::*;
#[path = "keymap_type/keymap_type_command.rs"]
mod keymap_type_command;
pub(crate) use keymap_type_command::*;
#[path = "keymap_type/keymap_type_binding.rs"]
mod keymap_type_binding;
pub(crate) use keymap_type_binding::*;
#[path = "keymap_lookup/keymap_lookup_bindings.rs"]
mod keymap_lookup_bindings;
pub(crate) use keymap_lookup_bindings::*;
#[path = "keymap_resolve/keymap_resolve_state.rs"]
mod keymap_resolve_state;
pub(crate) use keymap_resolve_state::*;
#[path = "keymap_resolve/keymap_resolve_methods.rs"]
mod keymap_resolve_methods;
pub(crate) use keymap_resolve_methods::*;
#[path = "keymap_name/keymap_name_key.rs"]
mod keymap_name_key;
pub(crate) use keymap_name_key::*;

#[cfg(test)]
#[path = "keymap_test/keymap_test_resolution.rs"]
mod tests;
