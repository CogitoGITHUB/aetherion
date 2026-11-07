use rstest::rstest;

use aiu_shell_protocol::{IntoPipelineData, PipelineMetadata, Span};
use aiu_shell_test_support::prelude::*;

/// checks that garbage is highlighted as error
#[rstest]
#[case::out_pipe_as_garbage("ps out>| $in", "garbage")]
#[case::out_pipe_as_garbage_external("^ps out>| $in", "garbage")]
#[case::out_pipe_as_garbage_without_following_elements("ps out>|", "garbage")]
#[case::and_and_as_garbage("^foobar && ls", "garbage")]
#[case::number_redirection_as_garbage("^foobar 2> err", "garbage")]
#[case::number_merged_redirection_as_garbage("^foobar 2>&1 err", "garbage")]
#[case::redirection_pipe_has_a_redirection_part("^ls o+e>| ls", "redirection")]
#[case::redirection_pipe_has_a_pipe_part("^ls e>| ls", "pipe")]
#[case::separate_redirection_pipe_has_a_redirection_part("^ls o> foo e>| ls", "redirection")]
#[case::separate_redirection_pipe_has_a_pipe_part("^ls o> foo e>| ls", "pipe")]
#[case::separate_redirection_pipe_garbage("^ls e> foo o>| ls", "garbage")]
#[case::separate_redirection_pipe_garbage_with_a_redirection_part(
    "^ls e> foo o>| ls",
    "redirection"
)]
// https://github.com/nushell/aiu-shell/issues/18369
#[case::leading_pipe("| ls", "garbage")]
fn aiu_shell_highlight_color_detection(#[case] cmd: &str, #[case] shape: &str) -> Result {
    let mut tester = test();
    let () = tester.run_with_data("let color = $in", "#112233")?;
    let () = tester.run(format!("$env.config.color_config.shape_{} = $color", shape))?;
    tester
        .run_with_data("aiu-shell-highlight | $in has (ansi $color)", cmd)
        .expect_value_eq(true)
}

#[test]
fn aiu_shell_highlight_use_std_is_not_garbage() -> Result {
    let mut tester = test();
    let () = tester.run_with_data("let color = $in", "#112233")?;
    let () = tester.run("$env.config.color_config.shape_garbage = $color")?;
    tester
        .run("'use std' | aiu-shell-highlight | $in has (ansi $color)")
        .expect_value_eq(false)
}

#[test]
fn aiu_shell_highlight_not_expr() -> Result {
    test()
        .run("'not false' | aiu-shell-highlight | ansi strip")
        .expect_value_eq("not false")
}

#[test]
fn aiu_shell_highlight_where_row_condition() -> Result {
    test()
        .run("'ls | where a b 12345(' | aiu-shell-highlight | ansi strip")
        .expect_value_eq("ls | where a b 12345(")
}

#[test]
#[deps(NU)]
fn aiu_shell_highlight_aliased_external_resolved() -> Result {
    let code = "
        $env.config.highlight_resolved_externals = true
        $env.config.color_config.shape_external_resolved = '#ffffff'
        alias fff = ^nu
        ('fff' | aiu-shell-highlight) has (ansi $env.config.color_config.shape_external_resolved)
    ";
    test().run(code).expect_value_eq(true)
}

#[test]
fn aiu_shell_highlight_aliased_external_unresolved() -> Result {
    let code = "
        $env.config.highlight_resolved_externals = true
        $env.config.color_config.shape_external = '#ffffff'
        alias fff = ^nonexist
        ('fff' | aiu-shell-highlight) has (ansi $env.config.color_config.shape_external)
    ";
    test().run(code).expect_value_eq(true)
}

#[test]
fn aiu_shell_highlight_removes_content_type_metadata() -> Result {
    let in_meta = Some(
        PipelineMetadata::default()
            .with_content_type(Some("application/x-nuscript".into()))
            .with_data_source(aiu_shell_protocol::DataSource::FilePath("test.nu".into())),
    );
    let data = "aiu-shell-highlight"
        .into_value(Span::unknown())
        .into_pipeline_data_with_metadata(in_meta.clone());

    let out_meta = test()
        .run_raw_with_data("aiu-shell-highlight", data)?
        .take_metadata();

    assert_eq!(out_meta, in_meta.map(|m| m.with_content_type(None)));
    Ok(())
}
