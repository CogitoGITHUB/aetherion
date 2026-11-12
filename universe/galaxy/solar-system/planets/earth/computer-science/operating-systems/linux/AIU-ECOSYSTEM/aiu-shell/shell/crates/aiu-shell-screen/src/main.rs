use aiu_shell_screen::clipboard_copy::copy_to_clipboard;
use aiu_shell_screen::input_state::InputState;
use aiu_shell_screen::screen_draw::draw_screen;
use crossterm::event::{self, DisableBracketedPaste, EnableBracketedPaste, Event, KeyCode, KeyEvent, KeyModifiers};
use crossterm::execute;
use std::io::stdout;
use std::time::Duration;
use ratatui::Terminal;
use ratatui::backend::TestBackend;

fn press_code(state: &mut InputState, code: KeyCode) {
    state.press(KeyEvent::new(code, KeyModifiers::NONE));
}

fn press_text(state: &mut InputState, text: &str) {
    for c in text.chars() {
        press_code(state, KeyCode::Char(c));
    }
}

fn scripted_state() -> InputState {
    let mut state = InputState::new();
    press_text(&mut state, "ttt");
    press_text(&mut state, "i");
    press_text(&mut state, " -a");
    press_code(&mut state, KeyCode::Enter);
    press_code(&mut state, KeyCode::Esc);
    press_text(&mut state, "t");
    press_text(&mut state, "ts");
    state
}

fn print_headless_screen(width: u16, height: u16) {
    let mut terminal = Terminal::new(TestBackend::new(width, height)).expect("test terminal");
    let state = scripted_state();
    terminal.draw(|frame| draw_screen(frame, &state)).expect("draw");
    let buffer = terminal.backend().buffer();
    for y in 0..height {
        let mut line = String::new();
        for x in 0..width {
            match buffer.cell((x, y)) {
                Some(cell) => line.push_str(cell.symbol()),
                None => line.push_str(" "),
            }
        }
        println!("{}", line.trim_end());
    }
}

fn run_screen() {
    if aiu_shell_screen::command_runner::enter_multiplexer() {
        return;
    }
    let mut terminal = ratatui::init();
    let _ = execute!(stdout(), EnableBracketedPaste);
    let mut state = InputState::new_running();
    loop {
        terminal.draw(|frame| draw_screen(frame, &state)).expect("draw");
        let incoming = if event::poll(Duration::from_millis(50)).unwrap_or(false) {
            Some(event::read().expect("event"))
        } else {
            None
        };
        state.poll_job();
        state.tick += 1;
        state.age_notice();
        if let Some(Event::Paste(text)) = &incoming {
            state.paste(text);
        }
        if let Some(Event::Key(key)) = incoming {
            state.press(key);
        }
        if let Some(line) = aiu_shell_screen::command_runner::take_fullscreen() {
            let _ = execute!(stdout(), DisableBracketedPaste);
            ratatui::restore();
            let code = aiu_shell_screen::command_runner::run_fullscreen(&line);
            terminal = ratatui::init();
            let _ = execute!(stdout(), EnableBracketedPaste);
            if let Some(last) = state.pairs.last_mut() {
                last.output.rows = vec![format!("full screen program ended, exit {}", code)];
            }
        }
        if aiu_shell_screen::command_runner::take_jump() { let _ = execute!(stdout(), DisableBracketedPaste); ratatui::restore(); let _ = aiu_shell_screen::command_runner::pick_directory(); terminal = ratatui::init(); let _ = execute!(stdout(), EnableBracketedPaste); } if let Some(text) = state.pending_copy.take() {
            copy_to_clipboard(&text);
        }
        if state.quit {
            break;
        }
    }
    let _ = execute!(stdout(), DisableBracketedPaste);
    ratatui::restore();
}

fn print_run_screen(line: &str, width: u16, height: u16) {
    let mut terminal = Terminal::new(TestBackend::new(width, height)).expect("test terminal");
    let mut state = InputState::new_running();
    press_text(&mut state, "i");
    press_text(&mut state, line);
    state.block_until_job_done = true;
    press_code(&mut state, KeyCode::Enter);
    terminal.draw(|frame| draw_screen(frame, &state)).expect("draw");
    let buffer = terminal.backend().buffer();
    for y in 0..height {
        let mut text = String::new();
        for x in 0..width {
            match buffer.cell((x, y)) {
                Some(cell) => text.push_str(cell.symbol()),
                None => text.push_str(" "),
            }
        }
        println!("{}", text.trim_end());
    }
}

fn print_search_screen(query: &str, running: bool, width: u16, height: u16) {
    let mut terminal = Terminal::new(TestBackend::new(width, height)).expect("test terminal");
    let mut state = if running {
        InputState::new_running()
    } else {
        InputState::new()
    };
    press_text(&mut state, "/");
    press_text(&mut state, query);
    terminal.draw(|frame| draw_screen(frame, &state)).expect("draw");
    let buffer = terminal.backend().buffer();
    for y in 0..height {
        let mut text = String::new();
        for x in 0..width {
            match buffer.cell((x, y)) {
                Some(cell) => text.push_str(cell.symbol()),
                None => text.push_str(" "),
            }
        }
        println!("{}", text.trim_end());
    }
}

fn print_colors_screen(width: u16, height: u16) {
    let mut terminal = Terminal::new(TestBackend::new(width, height)).expect("test terminal");
    let mut state = InputState::new();
    press_text(&mut state, "t");
    terminal.draw(|frame| draw_screen(frame, &state)).expect("draw");
    let buffer = terminal.backend().buffer();
    for y in 0..height {
        if let Some(cell) = buffer.cell((2, y)) {
            let style = cell.style();
            println!(
                "row {:>2} fg {:?} bold {} char {}",
                y,
                style.fg,
                style.add_modifier.contains(ratatui::style::Modifier::BOLD),
                cell.symbol()
            );
        }
    }
}

struct SinkWriter(std::rc::Rc<std::cell::RefCell<Vec<u8>>>);

impl std::io::Write for SinkWriter {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        self.0.borrow_mut().extend_from_slice(buf);
        Ok(buf.len())
    }

    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

fn print_bytes_screen() {
    let store = std::rc::Rc::new(std::cell::RefCell::new(Vec::new()));
    let backend = ratatui::backend::CrosstermBackend::new(SinkWriter(store.clone()));
    let area = ratatui::layout::Rect::new(0, 0, 60, 24);
    let options = ratatui::TerminalOptions {
        viewport: ratatui::Viewport::Fixed(area),
    };
    let mut terminal = Terminal::with_options(backend, options).expect("terminal");
    let mut state = InputState::new();
    press_text(&mut state, "t");
    terminal.draw(|frame| draw_screen(frame, &state)).expect("draw");
    let bytes = store.borrow().clone();
    let text = String::from_utf8_lossy(&bytes).to_string();
    println!("NO_COLOR set: {}", std::env::var_os("NO_COLOR").is_some());
    println!("total bytes: {}", bytes.len());
    println!("grey 110 codes: {}", text.matches("38;2;110;110;110").count());
    println!("white 255 codes: {}", text.matches("38;2;255;255;255").count());
    println!("bold codes: {}", text.matches("[1m").count());
    println!("any 38; codes: {}", text.matches("38;").count());
    let shown: String = text.replace("\u{1b}", "ESC").chars().take(260).collect();
    println!("start: {}", shown);
}

fn main() {
    unsafe {
        std::env::remove_var("NO_COLOR");
    }
    let mode = std::env::args().nth(1);
    if mode.as_deref() == Some("dump") {
        print_headless_screen(60, 24);
    } else if mode.as_deref() == Some("search") {
        let query = std::env::args().nth(2).unwrap_or_default();
        print_search_screen(&query, false, 60, 16);
    } else if mode.as_deref() == Some("searchdb") {
        let query = std::env::args().nth(2).unwrap_or_default();
        print_search_screen(&query, true, 60, 16);
    } else if mode.as_deref() == Some("dumpbytes") {
        print_bytes_screen();
    } else if mode.as_deref() == Some("dumpcolors") {
        print_colors_screen(60, 24);
    } else if mode.as_deref() == Some("run") {
        let line = std::env::args().nth(2).unwrap_or_default();
        print_run_screen(&line, 60, 12);
    } else {
        run_screen();
    }
}
