use aiu_shell_plugin::{JsonSerializer, serve_plugin};
use aiu_shell_plugin_inc::IncPlugin;

fn main() {
    serve_plugin(&IncPlugin, JsonSerializer {})
}
