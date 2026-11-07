use aiu_shell_protocol::{ByteStream, PipelineData, Signals, Span};
use aiu_shell_test_support::fs::Stub::FileWithContentToBeTrimmed;
use aiu_shell_test_support::playground::Playground;
use aiu_shell_test_support::prelude::*;
use pretty_assertions::assert_eq;

#[test]
fn parse_script_success() -> Result {
    Playground::setup("aiu_shell_check_test_1", |dirs, sandbox| {
        sandbox.with_files(&[FileWithContentToBeTrimmed(
            "script.nu",
            r#"
                greet "world"

                def greet [name] {
                  echo "hello" $name
                }
            "#,
        )]);

        test()
            .cwd(dirs.test())
            .run("aiu-shell-check script.nu")
            .expect_value_eq(true)
    })
}

#[test]
fn parse_script_with_wrong_type() -> Result {
    Playground::setup("aiu_shell_check_test_2", |dirs, sandbox| {
        sandbox.with_files(&[FileWithContentToBeTrimmed(
            "script.nu",
            r#"
                greet "world"

                def greet [name] {
                  echo "hello" $name
                }
            "#,
        )]);

        let err = test()
            .cwd(dirs.test())
            .run("aiu-shell-check --debug --as-module script.nu")
            .expect_shell_error()?;
        assert_eq!(err.generic_error()?, "Failed to parse content");

        Ok(())
    })
}
#[test]
fn parse_script_failure() -> Result {
    Playground::setup("aiu_shell_check_test_3", |dirs, sandbox| {
        sandbox.with_files(&[FileWithContentToBeTrimmed(
            "script.nu",
            r#"
                greet "world"

                def greet [name {
                  echo "hello" $name
                }
            "#,
        )]);

        let err = test()
            .cwd(dirs.test())
            .run("aiu-shell-check --debug script.nu")
            .expect_shell_error()?;
        let msg = err.generic_msg()?;
        assert!(
            msg.contains("Unclosed delimiter") || msg.contains("expected `]`"),
            "unexpected err: {msg}"
        );

        Ok(())
    })
}

#[test]
fn parse_module_success() -> Result {
    Playground::setup("aiu_shell_check_test_4", |dirs, sandbox| {
        sandbox.with_files(&[FileWithContentToBeTrimmed(
            "foo.nu",
            r#"
                # foo.nu

                export def hello [name: string] {
                    $"hello ($name)!"
                }

                export def hi [where: string] {
                    $"hi ($where)!"
                }
            "#,
        )]);

        test()
            .cwd(dirs.test())
            .run("aiu-shell-check --as-module foo.nu")
            .expect_value_eq(true)
    })
}

#[test]
fn parse_module_with_wrong_type() -> Result {
    Playground::setup("aiu_shell_check_test_5", |dirs, sandbox| {
        sandbox.with_files(&[FileWithContentToBeTrimmed(
            "foo.nu",
            r#"
                # foo.nu

                export def hello [name: string {
                    $"hello ($name)!"
                }

                export def hi [where: string] {
                    $"hi ($where)!"
                }
            "#,
        )]);

        let err = test()
            .cwd(dirs.test())
            .run("aiu-shell-check --debug foo.nu")
            .expect_shell_error()?;
        assert_eq!(err.generic_error()?, "Failed to parse content");

        Ok(())
    })
}
#[test]
fn parse_module_failure() -> Result {
    Playground::setup("aiu_shell_check_test_6", |dirs, sandbox| {
        sandbox.with_files(&[FileWithContentToBeTrimmed(
            "foo.nu",
            r#"
                # foo.nu

                export def hello [name: string {
                    $"hello ($name)!"
                }

                export def hi [where: string] {
                    $"hi ($where)!"
                }
            "#,
        )]);

        let err = test()
            .cwd(dirs.test())
            .run("aiu-shell-check --debug --as-module foo.nu")
            .expect_shell_error()?;
        let msg = err.generic_msg()?;
        assert!(
            msg.contains("Unclosed delimiter") || msg.contains("expected `]`"),
            "unexpected err: {msg}"
        );

        Ok(())
    })
}

#[test]
fn file_not_exist() -> Result {
    Playground::setup("aiu_shell_check_test_7", |dirs, _sandbox| {
        let err = test()
            .cwd(dirs.test())
            .run("aiu-shell-check --as-module foo.nu")
            .expect_io_error()?;
        assert_eq!(
            err.kind,
            aiu_shell_engine::command_prelude::ErrorKind::FileNotFound
        );
        Ok(())
    })
}

#[test]
fn parse_module_success_2() -> Result {
    Playground::setup("aiu_shell_check_test_10", |dirs, sandbox| {
        sandbox.with_files(&[FileWithContentToBeTrimmed(
            "foo.nu",
            r#"
                # foo.nu

                export-env { $env.MYNAME = "Arthur, King of the Britons" }
            "#,
        )]);

        test()
            .cwd(dirs.test())
            .run("aiu-shell-check --as-module foo.nu")
            .expect_value_eq(true)
    })
}

#[test]
fn parse_script_success_with_raw_stream() -> Result {
    let code = r#"
        greet "world"

        def greet [name] {
          echo "hello" $name
        }
    "#;
    test().run_with_data("aiu-shell-check", code).expect_value_eq(true)
}

#[test]
fn parse_module_success_with_raw_stream() -> Result {
    let code = r#"
        export def hello [name: string] {
            $"hello ($name)!"
        }

        export def hi [where: string] {
            $"hi ($where)!"
        }
    "#;
    test()
        .run_with_data("aiu-shell-check --as-module", code)
        .expect_value_eq(true)
}

#[test]
fn parse_string_as_script_success() -> Result {
    let code = "two\nlines";
    test().run_with_data("aiu-shell-check", code).expect_value_eq(true)
}

#[test]
fn parse_string_as_script() -> Result {
    let code = "two\nlines";
    let err = test()
        .run_with_data("aiu-shell-check --debug --as-module", code)
        .expect_shell_error()?;
    assert_eq!(err.generic_error()?, "Failed to parse content");
    Ok(())
}

#[test]
fn parse_module_success_with_internal_stream() -> Result {
    let code = r#"
        export def hello [name: string] {
            $"hello ($name)!"
        }

        export def hi [where: string] {
            $"hi ($where)!"
        }
    "#;

    test()
        .run_raw_with_data(
            "lines | aiu-shell-check --as-module",
            PipelineData::byte_stream(
                ByteStream::read_string(code.into(), Span::test_data(), Signals::empty()),
                None,
            ),
        )?
        .body
        .into_value(Span::test_data())
        .map_err(Into::into)
        .expect_value_eq(true)
}

#[test]
fn parse_script_success_with_complex_internal_stream() -> Result {
    let code = r#"
        #grep for nu
        def grep-nu [
            search   #search term
            entrada?  #file or pipe
            #
            #Examples
            #grep-nu search file.txt
            #ls **/* | some_filter | grep-nu search
            #open file.txt | grep-nu search
        ] {
            if ($entrada | is-empty) {
                if ($in | column? name) {
                    grep -ihHn $search ($in | get name)
                } else {
                    ($in | into string) | grep -ihHn $search
                }
            } else {
                grep -ihHn $search $entrada
            }
            | lines
            | parse "{file}:{line}:{match}"
            | str trim
            | update match {|f|
                $f.match
                | aiu-shell-highlight
            }
            | rename "source file" "line number"
        }
    "#;

    test()
        .run_raw_with_data(
            "lines | aiu-shell-check",
            PipelineData::byte_stream(
                ByteStream::read_string(code.into(), Span::test_data(), Signals::empty()),
                None,
            ),
        )?
        .body
        .into_value(Span::test_data())
        .map_err(Into::into)
        .expect_value_eq(true)
}

#[test]
fn parse_script_failure_with_complex_internal_stream() -> Result {
    let code = r#"
        #grep for nu
        def grep-nu [
            search   #search term
            entrada?  #file or pipe
            #
            #Examples
            #grep-nu search file.txt
            #ls **/* | some_filter | grep-nu search
            #open file.txt | grep-nu search
        ]
            if ($entrada | is-empty) {
                if ($in | column? name) {
                    grep -ihHn $search ($in | get name)
                } else {
                    ($in | into string) | grep -ihHn $search
                }
            } else {
                grep -ihHn $search $entrada
            }
            | lines
            | parse "{file}:{line}:{match}"
            | str trim
            | update match {|f|
                $f.match
                | aiu-shell-highlight
            }
            | rename "source file" "line number"
        }
    "#;

    test()
        .run_raw_with_data(
            "lines | aiu-shell-check",
            PipelineData::byte_stream(
                ByteStream::read_string(code.into(), Span::test_data(), Signals::empty()),
                None,
            ),
        )?
        .body
        .into_value(Span::test_data())
        .map_err(Into::into)
        .expect_value_eq(false)
}

#[test]
fn parse_script_success_with_complex_external_stream() -> Result {
    Playground::setup("aiu_shell_check_test_18", |dirs, sandbox| {
        sandbox.with_files(&[FileWithContentToBeTrimmed(
            "grep.nu",
            r#"
                #grep for nu
                def grep-nu [
                  search   #search term
                  entrada?  #file or pipe
                  #
                  #Examples
                  #grep-nu search file.txt
                  #ls **/* | some_filter | grep-nu search
                  #open file.txt | grep-nu search
                ] {
                  if ($entrada | is-empty) {
                    if ($in | column? name) {
                      grep -ihHn $search ($in | get name)
                    } else {
                      ($in | into string) | grep -ihHn $search
                    }
                  } else {
                      grep -ihHn $search $entrada
                  }
                  | lines
                  | parse "{file}:{line}:{match}"
                  | str trim
                  | update match {|f|
                      $f.match
                      | aiu-shell-highlight
                    }
                  | rename "source file" "line number"
                }

            "#,
        )]);

        test()
            .cwd(dirs.test())
            .run("open grep.nu | aiu-shell-check")
            .expect_value_eq(true)
    })
}

#[test]
fn parse_module_success_with_complex_external_stream() -> Result {
    Playground::setup("aiu_shell_check_test_19", |dirs, sandbox| {
        sandbox.with_files(&[FileWithContentToBeTrimmed(
            "grep.nu",
            r#"
                #grep for nu
                def grep-nu [
                  search   #search term
                  entrada?  #file or pipe
                  #
                  #Examples
                  #grep-nu search file.txt
                  #ls **/* | some_filter | grep-nu search
                  #open file.txt | grep-nu search
                ] {
                  if ($entrada | is-empty) {
                    if ($in | column? name) {
                      grep -ihHn $search ($in | get name)
                    } else {
                      ($in | into string) | grep -ihHn $search
                    }
                  } else {
                      grep -ihHn $search $entrada
                  }
                  | lines
                  | parse "{file}:{line}:{match}"
                  | str trim
                  | update match {|f|
                      $f.match
                      | aiu-shell-highlight
                    }
                  | rename "source file" "line number"
                }

            "#,
        )]);

        test()
            .cwd(dirs.test())
            .run("open grep.nu | aiu-shell-check --debug --as-module")
            .expect_value_eq(true)
    })
}

#[test]
fn parse_with_flag_success_for_complex_external_stream() -> Result {
    Playground::setup("aiu_shell_check_test_20", |dirs, sandbox| {
        sandbox.with_files(&[FileWithContentToBeTrimmed(
            "grep.nu",
            r#"
                #grep for nu
                def grep-nu [
                  search   #search term
                  entrada?  #file or pipe
                  #
                  #Examples
                  #grep-nu search file.txt
                  #ls **/* | some_filter | grep-nu search
                  #open file.txt | grep-nu search
                ] {
                  if ($entrada | is-empty) {
                    if ($in | column? name) {
                      grep -ihHn $search ($in | get name)
                    } else {
                      ($in | into string) | grep -ihHn $search
                    }
                  } else {
                      grep -ihHn $search $entrada
                  }
                  | lines
                  | parse "{file}:{line}:{match}"
                  | str trim
                  | update match {|f|
                      $f.match
                      | aiu-shell-highlight
                    }
                  | rename "source file" "line number"
                }

            "#,
        )]);

        test()
            .cwd(dirs.test())
            .run("open grep.nu | aiu-shell-check --debug")
            .expect_value_eq(true)
    })
}

#[test]
fn parse_with_flag_failure_for_complex_external_stream() -> Result {
    Playground::setup("aiu_shell_check_test_21", |dirs, sandbox| {
        sandbox.with_files(&[FileWithContentToBeTrimmed(
            "grep.nu",
            r#"
                #grep for nu
                def grep-nu
                  search   #search term
                  entrada?  #file or pipe
                  #
                  #Examples
                  #grep-nu search file.txt
                  #ls **/* | some_filter | grep-nu search
                  #open file.txt | grep-nu search
                ] {
                  if ($entrada | is-empty) {
                    if ($in | column? name) {
                      grep -ihHn $search ($in | get name)
                    } else {
                      ($in | into string) | grep -ihHn $search
                    }
                  } else {
                      grep -ihHn $search $entrada
                  }
                  | lines
                  | parse "{file}:{line}:{match}"
                  | str trim
                  | update match {|f|
                      $f.match
                      | aiu-shell-highlight
                    }
                  | rename "source file" "line number"
                }

            "#,
        )]);

        let err = test()
            .cwd(dirs.test())
            .run("open grep.nu | aiu-shell-check --debug")
            .expect_shell_error()?;
        assert_eq!(err.generic_error()?, "Failed to parse content");

        Ok(())
    })
}

#[test]
fn parse_with_flag_failure_for_complex_list_stream() -> Result {
    Playground::setup("aiu_shell_check_test_22", |dirs, sandbox| {
        sandbox.with_files(&[FileWithContentToBeTrimmed(
            "grep.nu",
            r#"
                #grep for nu
                def grep-nu
                  search   #search term
                  entrada?  #file or pipe
                  #
                  #Examples
                  #grep-nu search file.txt
                  #ls **/* | some_filter | grep-nu search
                  #open file.txt | grep-nu search
                ] {
                  if ($entrada | is-empty) {
                    if ($in | column? name) {
                      grep -ihHn $search ($in | get name)
                    } else {
                      ($in | into string) | grep -ihHn $search
                    }
                  } else {
                      grep -ihHn $search $entrada
                  }
                  | lines
                  | parse "{file}:{line}:{match}"
                  | str trim
                  | update match {|f|
                      $f.match
                      | aiu-shell-highlight
                    }
                  | rename "source file" "line number"
                }

            "#,
        )]);

        let err = test()
            .cwd(dirs.test())
            .run("open grep.nu | lines | aiu-shell-check --debug")
            .expect_shell_error()?;
        assert_eq!(err.generic_error()?, "Failed to parse content");

        Ok(())
    })
}

#[test]
fn parse_script_with_nested_scripts_success() -> Result {
    Playground::setup("aiu_shell_check_test_24", |dirs, sandbox| {
        sandbox
            .mkdir("lol")
            .with_files(&[FileWithContentToBeTrimmed(
                "lol/lol.nu",
                "
                    source-env ../foo.nu
                    use lol_shell.nu
                    overlay use ../lol/lol_shell.nu
                ",
            )])
            .with_files(&[FileWithContentToBeTrimmed(
                "lol/lol_shell.nu",
                r#"
                    export def ls [] { "lol" }
                "#,
            )])
            .with_files(&[FileWithContentToBeTrimmed(
                "foo.nu",
                "
                    $env.FOO = 'foo'
                ",
            )]);

        test()
            .cwd(dirs.test())
            .run("aiu-shell-check lol/lol.nu")
            .expect_value_eq(true)
    })
}

#[test]
fn aiu_shell_check_respects_file_pwd() -> Result {
    Playground::setup("aiu_shell_check_test_25", |dirs, sandbox| {
        sandbox
            .mkdir("lol")
            .with_files(&[FileWithContentToBeTrimmed(
                "lol/lol.nu",
                "
                    $env.RETURN = (aiu-shell-check ../foo.nu)
                ",
            )])
            .with_files(&[FileWithContentToBeTrimmed(
                "foo.nu",
                "
                    echo 'foo'
                ",
            )]);

        test()
            .cwd(dirs.test())
            .run("source-env lol/lol.nu; $env.RETURN")
            .expect_value_eq(true)
    })
}
#[test]
fn aiu_shell_check_module_dir() -> Result {
    Playground::setup("aiu_shell_check_test_26", |dirs, sandbox| {
        sandbox
            .mkdir("lol")
            .with_files(&[FileWithContentToBeTrimmed(
                "lol/mod.nu",
                "
                    export module foo.nu
                    export def main [] { 'lol' }
                ",
            )])
            .with_files(&[FileWithContentToBeTrimmed(
                "lol/foo.nu",
                "
                    export def main [] { 'lol foo' }
                ",
            )]);

        test()
            .cwd(dirs.test())
            .run("aiu-shell-check lol")
            .expect_value_eq(true)
    })
}
