//! One job: the module list — which area files belong to the crate.
//!
//! `#[path]` is used on purpose: every area file lives exactly where the tree
//! in the README lists it, so no per-area module file is invented
//! just to make the compiler happy. The reader must be able to find each file
//! by name in the register, and the register stays the source for it.
//!
//! Areas, lowest first. A module may use the ones below it and never the ones
//! above; gate/one-way-dependency-lint.nu enforces the same table for Racket.

#[path = "text/buffer.rs"]
pub mod buffer;

#[path = "text/positions.rs"]
pub mod positions;

#[path = "text/comments.rs"]
pub mod comments;

#[path = "parser/block-registry.rs"]
pub mod block_registry;

#[path = "parser/parser.rs"]
pub mod parser;

// reparse comes before partial: reparse asks partial what a slice cut.
#[path = "parser/reparse.rs"]
pub mod reparse;

#[path = "parser/partial.rs"]
pub mod partial;

#[path = "join/rust-exports.rs"]
pub mod rust_exports;

#[path = "rendering/strip.rs"]
pub mod strip;

#[path = "rendering/plain.rs"]
pub mod plain;

#[path = "rendering/rich.rs"]
pub mod rich;

// numbering comes after parser: it walks the tree the parser built.
#[path = "model/numbering.rs"]
pub mod numbering;

#[path = "database/record.rs"]
pub mod database_record;

#[path = "database/store.rs"]
pub mod database_store;

#[path = "database/file-format.rs"]
pub mod database_file_format;

#[path = "database/index-files.rs"]
pub mod database_index_files;

#[path = "database/index-blocks.rs"]
pub mod database_index_blocks;

#[path = "database/index-todos.rs"]
pub mod database_index_todos;

#[path = "database/index-tags.rs"]
pub mod database_index_tags;

#[path = "database/index-links.rs"]
pub mod database_index_links;

#[path = "database/index-names.rs"]
pub mod database_index_names;

#[path = "database/index-folder.rs"]
pub mod database_index_folder;
