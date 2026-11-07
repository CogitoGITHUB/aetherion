use aiu_shell_test_support::prelude::*;

#[test]
fn print_config_nu_default_to_stdout() -> Result {
    test()
        .run("config nu --default")
        .expect_value_eq(aiu_shell_config::ConfigFileKind::Config.default())
}
