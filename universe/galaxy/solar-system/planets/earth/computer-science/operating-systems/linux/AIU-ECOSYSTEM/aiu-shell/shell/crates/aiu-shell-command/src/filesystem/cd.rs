use std::path::PathBuf;

use aiu_shell_engine::command_prelude::*;
use aiu_shell_protocol::shell_error::{self, io::IoError};
use aiu_shell_utils::filesystem::{PermissionResult, have_permission};

#[derive(Clone)]
pub struct Cd;

impl Command for Cd {
    fn name(&self) -> &str {
        "cd"
    }

    fn description(&self) -> &str {
        "Change the current working directory."
    }

    fn search_terms(&self) -> Vec<&str> {
        vec!["change", "directory", "dir", "folder", "switch", "chdir"]
    }

    fn signature(&self) -> aiu_shell_protocol::Signature {
        Signature::build("cd")
            .input_output_types(vec![(Type::Nothing, Type::Nothing)])
            .switch("physical", "Use the physical directory structure; resolve symbolic links before processing instances of ..", Some('P'))
            .optional("path", SyntaxShape::Directory, "The path to change to.")
            .allow_variants_without_examples(true)
            .category(Category::FileSystem)
    }

    fn run(
        &self,
        engine_state: &EngineState,
        stack: &mut Stack,
        call: &Call,
        _input: PipelineData,
    ) -> Result<PipelineData, ShellError> {
        let physical = call.has_flag(engine_state, stack, "physical")?;
        let path_val = call
            .opt::<Spanned<String>>(engine_state, stack, 0)?
            .map(|p| p.map(aiu_shell_utils::strip_ansi_string_unlikely));

        // If getting PWD failed, default to the home directory. The user can
        // use `cd` to reset PWD to a good state.
        let cwd = engine_state
            .cwd(Some(stack))
            .ok()
            .or_else(aiu_shell_path::home_dir)
            .map(|path| path.into_std_path_buf())
            .unwrap_or_default();

        let path = match path_val {
            Some(v) => {
                if v.item == "-" {
                    if let Some(oldpwd) = stack.get_env_var(engine_state, "OLDPWD") {
                        oldpwd.to_path()?
                    } else {
                        cwd
                    }
                } else {
                    // Trim whitespace from the end of path.
                    let path_no_whitespace =
                        v.item.trim_end_matches(|x| matches!(x, '\x09'..='\x0d'));
                    // On Windows, resolve drive-relative paths like `d:` or `d:foo` the way cmd does.
                    let target = aiu_shell_path::resolve_drive_relative(
                        std::path::Path::new(path_no_whitespace),
                        &cwd,
                    );

                    // If `--physical` is specified, canonicalize the path; otherwise expand the path.
                    if physical {
                        if let Ok(path) = aiu_shell_path::canonicalize_with(&target, &cwd) {
                            if !path.is_dir() {
                                return Err(shell_error::io::IoError::new(
                                    shell_error::io::ErrorKind::from_std(
                                        std::io::ErrorKind::NotADirectory,
                                    ),
                                    v.span,
                                    None,
                                )
                                .into());
                            };
                            path
                        } else {
                            return Err(shell_error::io::IoError::new(
                                ErrorKind::DirectoryNotFound,
                                v.span,
                                PathBuf::from(path_no_whitespace),
                            )
                            .into());
                        }
                    } else {
                        let path = aiu_shell_path::expand_path_with(&target, &cwd, true);
                        let path = if path.exists() { path } else { aiu_shell_jump::directory_jump::best_match(path_no_whitespace).map(PathBuf::from).unwrap_or(path) };
                        if !path.exists() {
                            return Err(shell_error::io::IoError::new(
                                ErrorKind::DirectoryNotFound,
                                v.span,
                                PathBuf::from(path_no_whitespace),
                            )
                            .into());
                        };
                        if !path.is_dir() {
                            return Err(shell_error::io::IoError::new(
                                shell_error::io::ErrorKind::from_std(
                                    std::io::ErrorKind::NotADirectory,
                                ),
                                v.span,
                                path,
                            )
                            .into());
                        };
                        path
                    }
                }
            }
            None => aiu_shell_path::expand_tilde("~"),
        };

        // Set OLDPWD.
        // We're using `Stack::get_env_var()` instead of `EngineState::cwd()` to avoid a conversion roundtrip.
        if let Some(oldpwd) = stack.get_env_var(engine_state, "PWD") {
            stack.add_env_var("OLDPWD".into(), oldpwd.clone())
        }

        match have_permission(&path) {
            //FIXME: this only changes the current scope, but instead this environment variable
            //should probably be a block that loads the information from the state in the overlay
            PermissionResult::PermissionOk => {
                stack.set_cwd(&path)?;
                aiu_shell_jump::directory_jump::remember_directory(&path);
                Ok(PipelineData::empty())
            }
            PermissionResult::PermissionDenied => Err(IoError::new(
                shell_error::io::ErrorKind::from_std(std::io::ErrorKind::PermissionDenied),
                call.head,
                path,
            )
            .into()),
        }
    }

    fn examples(&self) -> Vec<Example<'_>> {
        vec![
            Example {
                description: "Change to your home directory.",
                example: "cd ~",
                result: None,
            },
            Example {
                description: r#"Change to the previous working directory (same as "cd $env.OLDPWD")."#,
                example: "cd -",
                result: None,
            },
            Example {
                description: "Changing directory with a custom command requires 'def --env'.",
                example: "def --env gohome [] { cd ~ }",
                result: None,
            },
            Example {
                description: "Move two directories up in the tree (the parent directory's parent). Additional dots can be added for additional levels.",
                example: "cd ...",
                result: None,
            },
            Example {
                description: "On Windows, switch to drive D:. Stays put if already on D:, otherwise goes to the current directory of D: inherited from the parent process, or its root.",
                example: "cd d:",
                result: None,
            },
            Example {
                description: "The cd command itself is often optional. Simply entering a path to a directory will cd to it.",
                example: "/home",
                result: None,
            },
        ]
    }
}
