use crate::*;

/// run_screen is one session's screen: it waits for that session's socket,
/// attaches, draws and answers the keys, and answers the client's exit code.
///
/// A switch is the same call on the next session's socket, so the owner moves
/// between sessions without leaving the client, and every wait ends on the
/// filesystem event that creates the socket (TODO item 49).
pub(crate) fn run_screen(state_dir: &Path, options: &Options, watch: bool) -> Result<i32, String> {
    let socket_path = state_dir.join("holder.sock");
    eprintln!(
        "client: waiting for the holder's socket at {}",
        socket_path.display()
    );
    wire::wait_for_socket(&socket_path)?;
    let fd = wire::connect(&socket_path)?;
    // The config comes with the screen: the file the environment names, else
    // the last good bake in this state directory, else the built-in defaults,
    // and the line says which one answered.
    let in_force = config::ConfigFile::start(state_dir);
    eprintln!("client: work mode, the config from {}", in_force.origin());
    let answer = screen::session(
        fd,
        CLIENT_NAME,
        watch,
        options.agent_program.clone(),
        options.editor_program.clone(),
        options.editor_mcp.clone(),
        in_force,
    );
    wire::close(fd);
    match answer? {
        screen::Ending::Left => Ok(0),
        screen::Ending::Refused(why) => {
            // A refusal is named and ends the client with the code the program
            // uses for one: 2, the same as the rest of the kit.
            eprintln!("client: refused: {}", why);
            Ok(2)
        }
        screen::Ending::Switch(to) => {
            eprintln!("client: switching to the session at {}", to.display());
            run_screen(&to, options, watch)
        }
    }
}

