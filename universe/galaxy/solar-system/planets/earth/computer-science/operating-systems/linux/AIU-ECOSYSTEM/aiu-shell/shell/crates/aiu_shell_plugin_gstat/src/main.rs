use aiu_shell_plugin::{MsgPackSerializer, serve_plugin};
use aiu_shell_plugin_gstat::GStatPlugin;

fn main() {
    serve_plugin(&GStatPlugin, MsgPackSerializer {})
}
