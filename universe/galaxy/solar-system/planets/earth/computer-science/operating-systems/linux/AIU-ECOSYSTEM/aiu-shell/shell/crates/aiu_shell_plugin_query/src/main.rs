use aiu_shell_plugin::{JsonSerializer, serve_plugin};
use aiu_shell_plugin_query::Query;

fn main() {
    serve_plugin(&Query {}, JsonSerializer {})
}
