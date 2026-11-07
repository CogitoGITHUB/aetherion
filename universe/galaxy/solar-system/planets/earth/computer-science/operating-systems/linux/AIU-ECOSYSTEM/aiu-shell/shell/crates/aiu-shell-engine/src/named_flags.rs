//! Re-exports signature-aware named flag helpers from `aiu-shell-protocol`.
//!
//! Kept as a thin module so existing `crate::named_flags::…` call sites stay stable.

pub use aiu_shell_protocol::engine::named_flags::*;
