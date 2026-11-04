use crate::*;

pub(crate) fn run_screen(state_dir: &Path, options: &Options, watch: bool) -> Result<i32, String> {
    let socket_path = state_dir.join("holder.sock");
    eprintln!(
        "client: waiting for the holder's socket at {}",
        socket_path.display()
    );
    wire::wait_for_socket(&socket_path)?;
    let fd = wire::connect(&socket_path)?;
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
            eprintln!("client: refused: {}", why);
            Ok(2)
        }
        screen::Ending::Switch(to) => {
            eprintln!("client: switching to the session at {}", to.display());
            run_screen(&to, options, watch)
        }
    }
}

