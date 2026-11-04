use crate::*;

/// engine_token answers the human's token: the environment first, then the
/// file in the sessions directory. The empty text means there is no token,
/// and a change is refused.
pub(crate) fn engine_token(sessions_dir: &PathBuf) -> String {
    match std::env::var("AIU_MULTIPLEXER_TOKEN") {
        Ok(from_env) if !from_env.is_empty() => from_env,
        _ => token_from_file(sessions_dir),
    }
}

/// token_from_file answers the token from the sessions directory, or the
/// empty text when the file is not there or holds nothing.
pub(crate) fn token_from_file(sessions_dir: &PathBuf) -> String {
    let file = sessions_dir.join("token");
    match std::fs::read_to_string(&file) {
        Ok(body) => body.trim().to_string(),
        Err(_) => String::new(),
    }
}

