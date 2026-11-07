mod contains;

use crate::PolarsPlugin;
use aiu_shell_plugin::PluginCommand;

pub use contains::ListContains;

pub(crate) fn list_commands() -> Vec<Box<dyn PluginCommand<Plugin = PolarsPlugin>>> {
    vec![Box::new(ListContains)]
}
