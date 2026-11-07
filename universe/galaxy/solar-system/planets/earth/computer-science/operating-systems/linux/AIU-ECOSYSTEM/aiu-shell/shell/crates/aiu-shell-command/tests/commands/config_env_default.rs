use aiu_shell_test_support::prelude::*;

#[test]
fn print_config_env_default_to_stdout() -> Result {
    test()
        .run("config env --default")
        .expect_value_eq(aiu_shell_config::ConfigFileKind::Env.default())
}
