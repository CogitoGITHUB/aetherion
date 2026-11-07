use aiu_shell_plugin::{MsgPackSerializer, serve_plugin};
use aiu_shell_plugin_formats::FormatCmdsPlugin;

fn main() {
    serve_plugin(&FormatCmdsPlugin, MsgPackSerializer {})
}
