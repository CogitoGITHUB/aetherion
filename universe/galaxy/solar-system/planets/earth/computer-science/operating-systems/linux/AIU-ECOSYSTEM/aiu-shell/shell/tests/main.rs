#![allow(non_snake_case)]
#![allow(clippy::unwrap_used)]

mod const_;
mod eval;
mod hooks;
mod integration;
mod modules;
mod overlays;
mod parsing;
mod path;
#[cfg(feature = "plugin")]
mod plugin_persistence;
#[cfg(feature = "plugin")]
mod plugins;
mod repl;
mod scope;
mod shell;

#[macro_use]
extern crate aiu_shell_test_support;
use aiu_shell_test_support::harness::main;
