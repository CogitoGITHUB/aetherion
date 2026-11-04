// One job: the screen — the panes drawn on one terminal, the mode line, the
// tab bar, the keymap explorer, and the redraw when something arrives.
//
// The screen holds nothing: the panes, their shells and their output belong
// to the holder. What lives here is what the owner sees and what the owner
// presses.
//
// The keys are read through the keymap (=keymap.rs=): the same table says
// what the keys do and what the explorer shows, so the two cannot drift
// apart. The modes are Visual (the multiplexer's own keys), Insert (the
// pane's own keys), Command (the command line) and Explorer (the keymap
// explorer).

use serde_json::{json, Value};
use std::io::Write;

use super::clipboard;
use super::keymap::{bindings, Command, Context, Keymap, Mode, Resolution, State};
use super::select::Selection;
use super::tty;
use super::wire;
use super::config::{ConfigFile, Reload};
use super::control;
use super::geometry;

/// ESCAPE leaves Insert, and cancels a sequence or the explorer.
const ESCAPE: u8 = 0x1b;
/// ENTER ends a command line.
const ENTER: u8 = 0x0d;
/// BACKSPACE takes the last character off the command line.
const BACKSPACE: u8 = 0x7f;
/// RESERVED_PREFIX is the escape hatch: the multiplexer keeps it in every
/// mode, so the owner can reach the multiplexer's own keys while a program
/// in the focused pane has the keyboard. Every other key in Insert belongs
/// to that program (rule 06).
const RESERVED_PREFIX: u8 = 0x02;
/// KEPT is how many lines of a pane's output the screen remembers.
const KEPT: usize = 400;

/// RING_KEPT is how many copies the multiplexer's own ring holds. The
/// ring is a small buffer: the newest copy is the first one.
const RING_KEPT: usize = 20;

/// VIEW_LINES is how many lines of a pane the agent's view carries: the
/// newest ones, each with the number the agent names it by.
const VIEW_LINES: usize = 40;

/// Ending is how the screen's life ended: the owner left, or the holder
/// refused the contracts and said why (TODO item 48).
pub enum Ending {
    /// Left is the owner's own leaving: the session goes on without them.
    Left,
    /// Refused is the holder's answer to a client whose contracts differ, in
    /// the holder's own words plus what to do about it.
    Refused(String),
    /// Switch is the owner moving this client to another session's socket
    /// (TODO item 49).
    Switch(std::path::PathBuf),
}

/// Action is what the client does with the holder after a key.
pub enum Action {
    Nothing,
    /// Send puts the bytes into the focused pane's own program.
    Send(Vec<u8>),
    /// Request asks the holder to do one thing.
    Request(Value),
    /// Quit leaves the multiplexer; the session goes on.
    Quit,
    /// AskEditor asks the editor what it owns, over the editor's own MCP
    /// server: the answer comes back as the editor's own words.
    AskEditor,
    /// Switch leaves this session's screen and attaches to another session.
    Switch(String),
    /// Terminal writes bytes to the owner's own terminal, never to a pane:
    /// the Android clipboard's sequence goes there, and a pane's program
    /// would print it instead of the clipboard taking it.
    Terminal(Vec<u8>),
}

/// PaneView is one pane as the screen sees it: its name, its tab, how much
/// of the layout it wants, and what its program said.
pub struct PaneView {
    pub name: String,
    pub tab: String,
    pub weight: u16,
    pub lines: Vec<String>,
    /// scroll is how many lines the view is back from the tail of the
    /// pane's lines. Zero is the tail: the newest words. The page keys
    /// move it, and the view shows the page the owner scrolled to.
    pub scroll: usize,
}

/// Panel is the box that lies over the panes: the keymap explorer, the
/// records, or the sessions.
struct Panel {
    title: String,
    lines: Vec<String>,
}

/// Screen is what the owner sees: the tabs, the panes of the current tab, the
/// focus, the mode, the command line, and the size of the window.
pub struct Screen {
    pub direction: String,
    pub tabs: Vec<String>,
    pub tab: usize,
    pub panes: Vec<PaneView>,
    pub focused: usize,
    pub mode: Mode,
    pub command: String,
    pub cols: u16,
    pub rows: u16,
    pub agent_program: String,
    pub editor_program: String,
    pub message: String,
    pub events: Vec<String>,
    /// select is the selection: the point, the mark and the region.
    pub select: Selection,
    /// ring is the multiplexer's own ring: what was copied, newest first.
    pub ring: Vec<String>,
    keymap: Keymap,
    panel: Option<Panel>,
    /// git is what the shared layer answered, and git_want is which view
    /// was asked for.
    git: Option<Value>,
    git_want: String,
    /// workspace is what the shared engine answered, and workspace_view is
    /// which view was asked for.
    workspace: Option<Value>,
    workspace_view: String,
    /// workspace_name is the workspace this session works on, and
    /// project_name is the project the context stands on. The mode line
    /// names both.
    workspace_name: String,
    /// sessions_dir is where this session stands with its siblings, as the
    /// holder said: a switch names another one in it (TODO item 49).
    sessions_dir: String,
    project_name: String,
    /// level is how much of the screen's own furniture is drawn. Level 1
    /// is the mode row and the tab bar; level 2 adds the specifics and
    /// the events; level 3 adds the hints. Level 0 draws no furniture at
    /// all: the panes take the whole screen, and the owner asked for
    /// that.
    level: u8,
    /// shows_tab_bar says whether the tab bar is drawn at level 1 and
    /// above. The config asks for it; level 0 hides it whatever the
    /// config says.
    shows_tab_bar: bool,
    /// reserved says that the owner pressed the reserved prefix: the next
    /// key is the multiplexer's own, whatever mode stands.
    reserved: bool,
    /// editor_mcp is the command that starts the editor's own MCP server:
    /// the program and what it runs. It is the seam the multiplexer asks
    /// the editor through.
    editor_mcp: Vec<String>,
    /// pending is the agent's request that waits for the state: the answer
    /// the agent gets is the state as it stands, not the state as it was.
    pending: Option<String>,
    /// fresh says the state arrived: the pending request may be answered.
    fresh: bool,
    /// pending_focus is the pane this screen just asked for, by name: the
    /// owner's own `pane new` is where the owner types next, so the focus
    /// goes there as soon as the state that holds it arrives.
    pending_focus: Option<String>,
    /// watch says this screen watches the session and cannot change it
    /// (TODO item 60): the drawing says so, the keys change nothing, and the
    /// holder refuses a change from this connection by name.
    watch: bool,
}

impl Screen {
    /// empty is a screen with nothing on it yet: the holder's state fills it
    /// in as soon as the state arrives.
    pub fn empty(
        agent_program: String,
        editor_program: String,
        editor_mcp: Vec<String>,
    ) -> Screen {
        Screen {
            direction: "row".to_string(),
            tabs: Vec::new(),
            tab: 0,
            panes: Vec::new(),
            focused: 0,
            mode: Mode::Visual,
            command: String::new(),
            cols: 0,
            rows: 0,
            agent_program,
            editor_program,
            message: String::new(),
            events: Vec::new(),
            reserved: false,
            select: Selection::new(),
            ring: Vec::new(),
            keymap: Keymap::empty(),
            panel: None,
            git: None,
            git_want: String::new(),
            workspace: None,
            workspace_view: String::new(),
            workspace_name: String::new(),
            sessions_dir: String::new(),
            project_name: String::new(),
            level: 2,
            shows_tab_bar: true,
            editor_mcp,
            pending: None,
            fresh: false,
            pending_focus: None,
            watch: false,
        }
    }

}

#[path = "screen_state/screen_state_settings.rs"]
mod screen_state_settings;
#[path = "screen_state/screen_state_records.rs"]
mod screen_state_records;
#[path = "screen_focus/screen_focus_lookup.rs"]
mod screen_focus_lookup;
#[path = "screen_paint/screen_paint_frame.rs"]
mod screen_paint_frame;
#[path = "screen_paint/screen_paint_scroll.rs"]
mod screen_paint_scroll;
#[path = "screen_paint/screen_paint_rows.rs"]
mod screen_paint_rows;
#[path = "screen_key/screen_key_input.rs"]
mod screen_key_input;
#[path = "screen_run/screen_run_command.rs"]
mod screen_run_command;
#[path = "screen_take/screen_take_answers.rs"]
mod screen_take_answers;
#[path = "screen_select/screen_select_region.rs"]
mod screen_select_region;
#[path = "screen_select/screen_select_paste.rs"]
mod screen_select_paste;
#[path = "screen_agent/screen_agent_open.rs"]
mod screen_agent_open;
#[path = "screen_control/screen_control_words.rs"]
mod screen_control_words;
#[path = "screen_session/screen_session_switch.rs"]
mod screen_session_switch;
#[path = "screen_pane/screen_pane_move.rs"]
mod screen_pane_move;

/// line_holds answers whether a record on the wire says a thing.
fn line_holds(line: &str, what: &str) -> bool {
    match serde_json::from_str::<Value>(line) {
        Ok(value) => value.get("what").and_then(|part| part.as_str()) == Some(what),
        Err(_) => false,
    }
}

/// agent_name answers the name of the agent program: the last piece of its
/// path. The target of a bundle is named, never inferred.
pub fn agent_name(program: &str) -> String {
    program
        .rsplit('/')
        .next()
        .filter(|name| !name.is_empty())
        .unwrap_or(program)
        .to_string()
}

/// clip answers the text with no more than width characters, and no more
/// than one line.
fn clip(text: &str, width: usize) -> String {
    // The escape sequences take no room on the screen, so they are not
    // counted, and they are never cut in half.
    let mut out = String::new();
    let mut count = 0;
    let mut characters = text.chars().peekable();
    while let Some(character) = characters.next() {
        if character == '\x1b' {
            out.push(character);
            for next in characters.by_ref() {
                out.push(next);
                if next.is_ascii_alphabetic() {
                    break;
                }
            }
            continue;
        }
        if count >= width {
            break;
        }
        out.push(character);
        count += 1;
    }
    out
}

/// first_line answers the first line of a text, for a message that names
/// what was copied.
fn first_line(text: &str) -> String {
    text.lines().next().unwrap_or("").to_string()
}

/// put answers the escape sequence that puts one line of text at one place
/// on the terminal.
fn put(out: &mut String, row: u16, left: u16, text: &str) {
    out.push_str(&format!("\x1b[{};{}H", row, left));
    out.push_str(text);
    out.push_str("\x1b[K");
}

/// session is the screen's own life: it attaches to the holder, draws the
/// panes, and answers the keys until the owner leaves.
///
/// The config comes in with the screen: it is applied before the first draw,
/// and it is looked at again before every other draw, so a change to the file
/// is in force without a restart. The check is the loop's, not a watcher's:
/// the loop turns on an event, and that is when the file is read.
pub fn session(
    fd: libc::c_int,
    client_name: &str,
    watch: bool,
    agent_program: String,
    editor_program: String,
    editor_mcp: Vec<String>,
    mut config: ConfigFile,
) -> Result<Ending, String> {
    let saved = tty::save_termios(libc::STDIN_FILENO).ok();
    let _ = tty::make_raw(libc::STDIN_FILENO);
    let mut screen = Screen::empty(agent_program, editor_program, editor_mcp);
    screen.set_level(config.config().level);
    screen.set_tab_bar(config.config().tab_bar);
    screen.set_watch(watch);
    // A config file that is there and was not used says so where the owner
    // reads it, and the screen runs on what the last good one said.
    if let Some(why) = config.problem() {
        screen.message = why.to_string();
    }
    wire::ask(fd, &json!({ "op": "state", "client": client_name }))?;
    wire::ask(
        fd,
        &json!({
            "op": "attach",
            "client": client_name,
            "role": if watch { "watch" } else { "screen" },
            "event-contract": crate::EVENT_CONTRACT,
            "holder-contract": crate::HOLDER_CONTRACT
        }),
    )?;

    let mut pending = String::new();
    let mut out = std::io::stdout();
    let mut leave = false;
    let mut detached = false;
    let mut keys_done = false;
    // A client that leaves must be heard: it detaches and waits for the
    // holder's answer, so a request it asked for is never lost to a
    // connection that closed too early.
    while !leave || !detached {
        // The window: the terminal's size is the session's size, and the
        // holder tells every pane — the shells and the editors alike.
        let size = tty::window_size(libc::STDOUT_FILENO).unwrap_or((80, 24));
        if size.0 != screen.cols || size.1 != screen.rows {
            screen.cols = size.0;
            screen.rows = size.1;
            // A watcher draws at its own size and asks for nothing: the
            // session's size belongs to the screen that types (TODO item 60).
            if !watch {
                // The rows the panes get: the window minus the screen's own
                // furniture. The holder gives every program the size of the
                // place it is drawn in, so the two cannot drift apart.
                let (_, area_rows) = screen.area();
                wire::ask(
                    fd,
                    &json!({
                        "op": "resize",
                        "client": client_name,
                        "cols": size.0,
                        "rows": size.1,
                        "area-rows": area_rows
                    }),
                )?;
            }
        }

        // The keys are only read once the screen knows the panes: a key that
        // arrives before the state would go to a pane the screen has not met.
        let ready = !screen.panes.is_empty() && !keys_done;
        let mut fds = vec![libc::pollfd {
            fd,
            events: libc::POLLIN,
            revents: 0,
        }];
        if ready {
            fds.push(libc::pollfd {
                fd: libc::STDIN_FILENO,
                events: libc::POLLIN,
                revents: 0,
            });
        }
        let ready_poll = unsafe { libc::poll(fds.as_mut_ptr(), fds.len() as libc::nfds_t, -1) };
        if ready_poll < 0 {
            if std::io::Error::last_os_error().raw_os_error() == Some(libc::EINTR) {
                continue;
            }
            break;
        }

        if fds[0].revents & (libc::POLLIN | libc::POLLHUP) != 0 {
            let mut buffer = [0u8; 8192];
            let got = wire::read(fd, &mut buffer)?;
            if got == 0 {
                break;
            }
            pending.push_str(&String::from_utf8_lossy(&buffer[..got]));
            while let Some(at) = pending.find('\n') {
                let line = pending[..at].trim().to_string();
                pending = pending[at + 1..].to_string();
                if line.is_empty() {
                    continue;
                }
                // The agent's request is not a record of the session: it is
                // the agent's words, and the screen runs them the way the
                // owner's own keys run them.
                let asked: Value = match serde_json::from_str(&line) {
                    Ok(found) => found,
                    Err(_) => Value::Null,
                };
                if control::is_request(&asked) {
                    let (id, words) = control::request_of(&asked);
                    let outcome = control::run(&mut screen, &words);
                    if let Some(mut ask) = outcome.ask {
                        ask["client"] = Value::from(client_name);
                        wire::ask(fd, &ask)?;
                    }
                    // The state is asked for, so the answer the agent gets is
                    // the state as it stands and not the state as it was.
                    screen.wait_for_state(id);
                    wire::ask(fd, &json!({ "op": "state", "client": client_name }))?;
                    continue;
                }
                if let Some(why) = take_record(&mut screen, &line) {
                    // The holder refused the contracts: the client says so in
                    // the holder's own words and stops drawing, because a
                    // picture from a session it does not understand is a lie.
                    out.write_all(b"\x1b[?25h\x1b[0m\n").ok();
                    let _ = out.flush();
                    if let Some(settings) = saved.clone() {
                        let _ = tty::restore_termios(libc::STDIN_FILENO, &settings);
                    }
                    return Ok(Ending::Refused(why));
                }
                if let Some(id) = screen.take_pending() {
                    let data = screen.view();
                    wire::ask(fd, &control::answer(&id, &data))?;
                }
                if line_holds(&line, "the client detached") {
                    detached = true;
                }
            }
        }

        // A pipe that is at its end says POLLHUP, not POLLIN: the end of the
        // keys is an event too, and the client must hear it.
        if fds.len() > 1 && fds[1].revents & (libc::POLLIN | libc::POLLHUP) != 0 {
            let mut buffer = [0u8; 1024];
            let got = wire::read(libc::STDIN_FILENO, &mut buffer)?;
            if got == 0 {
                // The keys are over: the client detaches and waits to be
                // answered, and the wait ends on the answer.
                keys_done = true;
                if !leave {
                    leave = true;
                    wire::ask(fd, &json!({ "op": "detach", "client": client_name }))?;
                }
                continue;
            }
            for action in screen.key(&buffer[..got]) {
                // A watcher watches: every key that would change the session
                // is answered with the rule, and only leaving is done
                // (TODO item 60). The holder refuses the same things on its
                // own, so the rule holds even if a request slips past here.
                let action = match screen.watch_filter(action) {
                    Some(one) => one,
                    None => continue,
                };
                match action {
                    Action::Nothing => {}
                    Action::Send(bytes) => {
                        let text = String::from_utf8_lossy(&bytes).to_string();
                        wire::ask(
                            fd,
                            &json!({
                                "op": "send",
                                "client": client_name,
                                "pane": screen.focused_pane(),
                                "data": text
                            }),
                        )?;
                    }
                    Action::Request(request) => {
                        let mut request = request;
                        request["client"] = Value::from(client_name);
                        wire::ask(fd, &request)?;
                    }
                    Action::Switch(name) => {
                        let to = std::path::Path::new(&screen.sessions_dir).join(&name);
                        out.write_all(b"\x1b[?25h\x1b[0m\n").ok();
                        let _ = out.flush();
                        if let Some(settings) = saved.clone() {
                            let _ = tty::restore_termios(libc::STDIN_FILENO, &settings);
                        }
                        return Ok(Ending::Switch(to));
                    }
                    Action::Terminal(bytes) => {
                        // The clipboard's sequence belongs to the owner's
                        // terminal: it is written where the drawing goes,
                        // never into a pane's program.
                        let _ = out.write_all(&bytes);
                        let _ = out.flush();
                    }
                    Action::AskEditor => {
                        // The holder asks the editor, not the client: the
                        // client holds no child process, and the command
                        // that starts the editor's server is only a word
                        // here.
                        let command = screen.editor_mcp.clone();
                        wire::ask(
                            fd,
                            &json!({
                                "op": "editor",
                                "client": client_name,
                                "command": command,
                                "capability": "dashboard"
                            }),
                        )?;
                    }
                    Action::Quit => {
                        leave = true;
                        keys_done = true;
                        wire::ask(fd, &json!({ "op": "detach", "client": client_name }))?;
                    }
                }
            }
        }

        // The config is looked at once per turn of the loop, before the
        // drawing: a file that changed is in force at this draw, and a file
        // that does not parse leaves the values in force and says why in the
        // message line. No timer and no thread: the loop turns on an event.
        match config.reload_if_changed() {
            Reload::Unchanged => {}
            Reload::Changed(now) => {
                screen.set_level(now.level);
                screen.set_tab_bar(now.tab_bar);
                let from = config.path().display();
                screen.message = format!("the config was reloaded from {}", from);
            }
            Reload::Broken(why) => {
                screen.message = format!("the config is not used: {}", why);
            }
        }

        let drawing = screen.draw();
        let _ = out.write_all(drawing.as_bytes());
        let _ = out.flush();
    }

    out.write_all(b"\x1b[?25h\x1b[0m\n").ok();
    let _ = out.flush();
    if let Some(settings) = saved {
        let _ = tty::restore_termios(libc::STDIN_FILENO, &settings);
    }
    Ok(Ending::Left)
}

/// refusal_text answers the holder's refusal of the contracts, in one line that
/// says both builds and what to do, and None for any other record: a client
/// that meets a holder it does not agree with must not go on drawing.
pub fn refusal_text(record: &Value) -> Option<String> {
    let what = record.get("what").and_then(|value| value.as_str())?;
    if what != "the client and the holder do not agree on the contract" {
        return None;
    }
    let inputs = record.get("inputs").cloned().unwrap_or(Value::Null);
    let outputs = record.get("outputs").cloned().unwrap_or(Value::Null);
    let said = |value: &Value, key: &str| {
        value
            .get(key)
            .and_then(|one| one.as_str())
            .unwrap_or("")
            .to_string()
    };
    let safe = record
        .get("result")
        .and_then(|result| result.get("safe-path"))
        .and_then(|one| one.as_str())
        .unwrap_or("finish the session and restart the holder");
    Some(format!(
        "the contracts differ — this client is {} and {}, the holder is {} and {}; {}",
        said(&inputs, "client-holder-contract"),
        said(&inputs, "client-event-contract"),
        said(&outputs, "holder-holder-contract"),
        said(&outputs, "holder-event-contract"),
        safe
    ))
}

/// take_record reads one record from the holder into the screen.
///
/// Every record is shown: the program's output goes into the pane it came
/// from, and the event itself goes into the events strip, so nothing that
/// happened is silent (rule 01: nothing important is silent).
fn take_record(screen: &mut Screen, line: &str) -> Option<String> {
    let record: Value = match serde_json::from_str(line) {
        Ok(found) => found,
        Err(_) => return None,
    };
    if let Some(why) = refusal_text(&record) {
        return Some(why);
    }
    let kind = record.get("kind").and_then(|value| value.as_str()).unwrap_or("");
    let who = record.get("who").and_then(|value| value.as_str()).unwrap_or("");
    let what = record.get("what").and_then(|value| value.as_str()).unwrap_or("");
    let why = record.get("why").and_then(|value| value.as_str()).unwrap_or("");
    let seq = record.get("seq").and_then(|value| value.as_u64()).unwrap_or(0);
    screen
        .events
        .push(format!("#{} {} {}: {} — {}", seq, kind, who, what, why));
    if screen.events.len() > 50 {
        let extra = screen.events.len() - 50;
        screen.events.drain(0..extra);
    }
    if kind == "progress" {
        let text = record
            .get("outputs")
            .and_then(|outputs| outputs.get("text"))
            .and_then(|value| value.as_str())
            .unwrap_or("");
        screen.push_text(who, text);
        return None;
    }
    if what == "the workspace was read" {
        screen.take_workspace(&record);
    }
    if what == "the git state was read" {
        screen.take_git(&record);
        return None;
    }
    if what == "the sessions were listed" {
        screen.take_sessions(&record);
        return None;
    }
    if what == "the pane was read back" {
        screen.take_rewind(&record);
        return None;
    }
    if what == "the editor was asked" {
        screen.take_editor(&record);
        return None;
    }
    if who == "holder" {
        screen.take_state(&record);
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    /// a_screen is a screen on a window big enough to draw one pane, so the
    /// drawing can be read for what it holds.
    fn a_screen() -> Screen {
        let mut screen = Screen::empty("opencode".to_string(), "editor".to_string(), Vec::new());
        screen.cols = 60;
        screen.rows = 12;
        screen.tabs = vec!["main".to_string()];
        screen.panes = vec![PaneView {
            name: "work".to_string(),
            tab: "main".to_string(),
            weight: 1,
            lines: Vec::new(),
            scroll: 0,
        }];
        screen
    }

    #[test]
    fn the_config_sets_the_level_and_the_tab_bar() {
        let mut screen = a_screen();
        screen.set_level(0);
        screen.set_tab_bar(false);
        assert_eq!(screen.level(), 0);
        assert_eq!(screen.tab_bar_on(), false);
        let drawing = screen.draw();
        assert!(drawing.contains("VISUAL") == false, "no mode row: {:?}", drawing);
        assert!(drawing.contains("[main]") == false, "no tab bar: {:?}", drawing);
    }

    #[test]
    fn a_pane_the_owner_asked_for_takes_the_focus_when_the_state_arrives() {
        let mut screen = a_screen();
        screen.pending_focus = Some("pane-2".to_string());
        screen.take_state(&json!({
            "outputs": {
                "session": "mux--bin-sh-1",
                "tabs": ["main"],
                "panes": [
                    { "name": "main", "tab": "main", "weight": 1, "lines": [], "scroll": 0 },
                    { "name": "pane-2", "tab": "main", "weight": 1, "lines": [], "scroll": 0 }
                ]
            }
        }));
        assert_eq!(screen.focused_pane(), "pane-2", "the new pane is where the owner types");
        assert_eq!(screen.pending_focus, None, "the ask is spent");
    }

    #[test]
    fn a_level_above_three_is_taken_as_three() {
        let mut screen = a_screen();
        screen.set_level(9);
        assert_eq!(screen.level(), 3);
    }

    #[test]
    fn the_tab_bar_can_be_off_while_the_mode_row_stays() {
        let mut screen = a_screen();
        screen.set_level(2);
        screen.set_tab_bar(false);
        let drawing = screen.draw();
        assert!(drawing.contains("VISUAL"), "the mode row stays: {:?}", drawing);
        assert!(drawing.contains("[main]") == false, "the tab bar is gone: {:?}", drawing);
    }

    /// a_screen_with_words is a screen whose focused pane said forty
    /// numbered lines, so a page is a page and there is something to
    /// scroll to.
    fn a_screen_with_words() -> Screen {
        let mut screen = a_screen();
        screen.panes[0].lines = (1..=40).map(|at| format!("line {}", at)).collect();
        screen
    }

    #[test]
    fn the_page_key_scrolls_the_view_to_the_older_words() {
        let mut screen = a_screen_with_words();
        let before = screen.window(0, 6);
        assert_eq!(before.first(), Some(&"line 35".to_string()));
        assert!(screen.scroll_view(true), "the view moved");
        let after = screen.window(0, 6);
        assert_eq!(after.first(), Some(&"line 29".to_string()));
        assert_eq!(after.last(), Some(&"line 34".to_string()));
    }

    #[test]
    fn the_view_stops_at_the_oldest_page() {
        let mut screen = a_screen_with_words();
        let mut moved = true;
        let mut pages = 0;
        while moved {
            moved = screen.scroll_view(true);
            if moved {
                pages = pages + 1;
            }
        }
        assert!(pages > 0, "the view moved at least once");
        assert_eq!(screen.scroll_distance(), 34);
        let oldest = screen.window(0, 6);
        assert_eq!(oldest.first(), Some(&"line 1".to_string()));
    }

    #[test]
    fn the_pick_restarts_over_the_fresh_text() {
        let mut screen = a_screen_with_words();
        screen.mode = Mode::Select;
        screen.select.right(&screen.select_lines());
        screen.select.set_mark();
        assert!(screen.select.mark().is_some(), "the mark stands");
        assert!(screen.scroll_view(true), "the view moved");
        screen.select.restart();
        assert_eq!(screen.select.point, (0, 0));
        assert!(screen.select.mark().is_none(), "the mark is gone");
    }

    /// a_picked_screen is a screen holding one line of the given length, with
    /// the whole line picked: the mark at its start and the point at its end.
    fn a_picked_screen(width: usize) -> Screen {
        let mut screen = a_screen();
        let text: String = "x".repeat(width);
        screen.panes[0].lines = vec![text];
        screen.mode = Mode::Select;
        screen.select.set_mark();
        screen.select.point = (0, width);
        screen
    }

    #[test]
    fn the_pick_goes_out_to_the_android_clipboard_as_one_sequence() {
        let mut screen = a_picked_screen(11);
        let action = screen.run(Command::SelectCopyOut);
        let bytes = match action {
            Action::Terminal(bytes) => bytes,
            _ => panic!("the copy out writes the terminal"),
        };
        let said = String::from_utf8(bytes).unwrap();
        assert!(said.starts_with("\x1b]52;c;"), "the OSC 52 prefix: {:?}", said);
        assert!(said.ends_with('\x07'), "the bell ends it: {:?}", said);
        assert_eq!(
            screen.ring.first(),
            Some(&"xxxxxxxxxxx".to_string()),
            "the ring holds the same pick"
        );
        assert!(screen.message.contains("clipboard"), "the line: {:?}", screen.message);
    }

    #[test]
    fn a_pick_over_the_limit_is_refused_by_name_and_the_ring_keeps_it() {
        let mut screen = a_picked_screen(7000);
        let action = screen.run(Command::SelectCopyOut);
        assert!(matches!(action, Action::Nothing), "nothing goes to the terminal");
        assert!(screen.message.contains("8192"), "the limit: {:?}", screen.message);
        assert_eq!(screen.ring.len(), 1, "the owner's own copy is not lost");
    }

    #[test]
    fn an_empty_android_clipboard_is_said_and_nothing_is_sent() {
        let mut screen = a_screen();
        let action = screen.paste_text(String::new());
        assert!(matches!(action, Action::Nothing), "nothing is sent");
        assert!(screen.message.contains("empty"), "the line: {:?}", screen.message);
    }

    #[test]
    fn a_paste_over_the_limit_is_refused_with_the_numbers() {
        let mut screen = a_screen();
        let action = screen.paste_text("x".repeat(clipboard::PASTE_MAX + 1));
        assert!(matches!(action, Action::Nothing), "nothing is sent");
        assert!(screen.message.contains("65536"), "the limit: {:?}", screen.message);
    }

    #[test]
    fn a_session_word_asks_the_holder_for_that_command() {
        let mut screen = a_screen();
        let action = screen.run_command("session create second");
        match action {
            Action::Request(request) => {
                assert_eq!(request["op"], "session");
                assert_eq!(request["what"], "create");
                assert_eq!(request["name"], "second");
            }
            _ => panic!("a session word is one request"),
        }
    }

    #[test]
    fn a_switch_needs_the_sessions_directory_the_holder_named() {
        let mut screen = a_screen();
        let action = screen.run_command("session switch second");
        assert!(matches!(action, Action::Nothing), "nothing is switched yet");
        assert!(screen.message.contains("did not say"), "the line: {:?}", screen.message);
        screen.sessions_dir = "/tmp/opencode/sessions".to_string();
        let action = screen.run_command("session switch second");
        match action {
            Action::Switch(name) => assert_eq!(name, "second"),
            _ => panic!("the switch is its own action"),
        }
    }

    #[test]
    fn a_session_name_with_a_slash_is_refused_by_name() {
        let mut screen = a_screen();
        let action = screen.run_command("session kill a/b");
        assert!(matches!(action, Action::Nothing), "nothing is asked");
        assert!(screen.message.contains("not a session name"), "the line: {:?}", screen.message);
    }

    #[test]
    fn a_contract_refusal_is_answered_in_both_versions_and_what_to_do() {
        let record = json!({
            "kind": "fail",
            "who": "holder",
            "what": "the client and the holder do not agree on the contract",
            "inputs": {
                "client-event-contract": "event-log-format/1",
                "client-holder-contract": "multiplexer-holder/1"
            },
            "outputs": {
                "holder-event-contract": "event-log-format/2",
                "holder-holder-contract": "multiplexer-holder/2"
            },
            "result": { "safe-path": "finish the session and restart the holder" }
        });
        let why = refusal_text(&record).expect("the refusal is named");
        assert!(why.contains("multiplexer-holder/1"), "the client's: {:?}", why);
        assert!(why.contains("multiplexer-holder/2"), "the holder's: {:?}", why);
        assert!(why.contains("event-log-format/2"), "both events: {:?}", why);
        assert!(why.contains("restart the holder"), "what to do: {:?}", why);
    }

    #[test]
    fn a_record_that_is_not_a_refusal_is_not_taken_for_one() {
        let record = json!({ "kind": "info", "what": "the records were read" });
        assert!(refusal_text(&record).is_none(), "no refusal here");
    }

    #[test]
    fn a_rewind_asks_the_holder_for_that_pane_at_that_record() {
        let mut screen = a_screen();
        let action = screen.run_command("rewind work 12");
        match action {
            Action::Request(request) => {
                assert_eq!(request["op"], "rewind");
                assert_eq!(request["pane"], "work");
                assert_eq!(request["seq"], 12);
            }
            _ => panic!("the rewind is one request"),
        }
        assert!(screen.message.contains("record 12"), "the line: {:?}", screen.message);
    }

    #[test]
    fn a_rewind_of_a_number_that_is_not_a_record_is_refused_by_name() {
        let mut screen = a_screen();
        let action = screen.run_command("rewind work later");
        assert!(matches!(action, Action::Nothing), "nothing is asked");
        assert!(screen.message.contains("not a record number"), "the line: {:?}", screen.message);
    }

    #[test]
    fn a_rewind_of_a_pane_that_is_not_there_is_refused_by_name() {
        let mut screen = a_screen();
        let action = screen.run_command("rewind nowhere 3");
        assert!(matches!(action, Action::Nothing), "nothing is asked");
        assert!(screen.message.contains("no pane named nowhere"), "the line: {:?}", screen.message);
    }

    #[test]
    fn the_rewind_panel_shows_the_journal_and_leaves_the_live_pane_alone() {
        let mut screen = a_screen_with_words();
        let before = screen.panes[0].lines.clone();
        let record = json!({
            "kind": "info",
            "who": "holder",
            "what": "the pane was read back",
            "seq": 12,
            "outputs": { "pane": "work", "seq": 12, "count": 2,
                         "lines": ["line 1", "line 2"] }
        });
        screen.take_rewind(&record);
        let panel = screen.panel.as_ref().expect("the panel is there");
        assert!(panel.title.contains("record 12"), "the title: {:?}", panel.title);
        let shown = panel.lines.join("\n");
        assert!(shown.contains("line 1"), "the journal's own line: {:?}", shown);
        assert!(shown.contains("not changed"), "the live pane is named: {:?}", shown);
        assert_eq!(screen.panes[0].lines, before, "the live pane keeps its own lines");
    }

    #[test]
    fn a_paste_goes_to_the_focused_pane_in_one_request() {
        let mut screen = a_screen();
        let action = screen.paste_text("the words".to_string());
        match action {
            Action::Request(request) => {
                assert_eq!(request["op"], "send");
                assert_eq!(request["pane"], "work");
                assert_eq!(request["data"], "the words");
            }
            _ => panic!("the paste is one request"),
        }
    }

    #[test]
    fn a_watching_screen_says_so_and_changes_nothing() {
        let mut screen = a_screen();
        screen.set_watch(true);
        let drawing = screen.draw();
        assert!(drawing.contains("WATCH/"), "the mode row says it watches: {:?}", drawing);
        // Every action that would change the session is taken away, and the
        // message says the rule; leaving is still done.
        let left = screen.watch_filter(Action::Quit);
        assert!(matches!(left, Some(Action::Quit)), "leaving is not a change");
        let taken = screen.watch_filter(Action::Send(b"rm -rf /".to_vec()));
        assert!(taken.is_none(), "a watcher's send is taken away");
        assert!(
            screen.message.contains("cannot change it"),
            "the message names the rule: {:?}",
            screen.message
        );
    }

    #[test]
    fn a_screen_that_is_not_watching_keeps_every_action() {
        let mut screen = a_screen();
        let sent = screen.watch_filter(Action::Send(b"echo hi".to_vec()));
        match sent {
            Some(Action::Send(bytes)) => assert_eq!(bytes, b"echo hi"),
            _ => panic!("the owner's own key is not taken away"),
        }
        assert!(screen.message.is_empty(), "no message is made up: {:?}", screen.message);
    }
}
