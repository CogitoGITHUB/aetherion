#![doc = include_str!("../README.md")]
pub mod extra;
pub use extra::*;

#[cfg(test)]
#[macro_use]
extern crate aiu_shell_test_support;

#[cfg(test)]
use aiu_shell_test_support::harness::main;
