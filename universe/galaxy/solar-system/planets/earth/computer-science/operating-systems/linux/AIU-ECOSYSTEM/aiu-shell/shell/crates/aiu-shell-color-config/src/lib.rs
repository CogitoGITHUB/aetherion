#![doc = include_str!("../README.md")]
mod color_config;
mod matching_brackets_style;
mod aiu_shell_style;
mod shape_color;
mod style_computer;
mod text_style;

pub use color_config::*;
pub use matching_brackets_style::*;
pub use aiu_shell_style::*;
pub use shape_color::*;
pub use style_computer::*;
pub use text_style::*;

#[cfg(test)]
#[macro_use]
extern crate aiu_shell_test_support;

#[cfg(test)]
use aiu_shell_test_support::harness::main;
