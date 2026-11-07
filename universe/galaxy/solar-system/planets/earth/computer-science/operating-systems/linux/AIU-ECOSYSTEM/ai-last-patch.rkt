#lang racket/base
(require racket/file racket/string)
(define crate "aiu-shell/shell/crates/aiu-shell-screen/src")
(define bar-path (string-append crate "/bar_view.rs"))
(define state-path (string-append crate "/input_state.rs"))
(define draw-path (string-append crate "/screen_draw.rs"))
(define todo-path "aiu-shell/todo.aiu")
(define readme-path "aiu-shell/shell/README.md")
(define starting-path "ai-starting-point.md")
(define (fail message) (eprintf "FAILED: ~a\n" message) (exit 1))
(define (count-of old text) (length (regexp-match* (regexp (regexp-quote old)) text)))
(define (once text old new label)
  (unless (= (count-of old text) 1) (fail (string-append "anchor failed: " label)))
  (string-replace text old new))
(define bar-add #<<X

static FULL_INPUT: AtomicBool = AtomicBool::new(false);

pub fn toggle_full_input() {
    FULL_INPUT.fetch_xor(true, Ordering::Relaxed);
}

pub fn open_full_input() {
    FULL_INPUT.store(true, Ordering::Relaxed);
}

pub fn draw_full_input(frame: &mut Frame, state: &InputState, area: Rect) {
    if !FULL_INPUT.load(Ordering::Relaxed) || state.mode == Mode::Search {
        return;
    }
    let width = area.width as usize;
    if width < 8 || area.height < 4 {
        return;
    }
    let inner = width - 3;
    let mut rows: Vec<String> = Vec::new();
    for part in state.text.split(char::from(10u8)) {
        let chars: Vec<char> = part.chars().collect();
        if chars.is_empty() {
            rows.push(String::new());
        }
        for piece in chars.chunks(inner) {
            rows.push(piece.iter().collect());
        }
    }
    if state.mode == Mode::Insert {
        let full = rows.last().map(|row| row.chars().count() >= inner).unwrap_or(true);
        if full {
            rows.push(String::from("█"));
        } else if let Some(last) = rows.last_mut() {
            last.push_str("█");
        }
    }
    let keep = area.height as usize - 2;
    if rows.len() > keep {
        let extra = rows.len() - keep;
        rows.drain(0..extra);
    }
    let frame_box = crate::box_frame::BoxFrame {
        title: String::from("full input  esc visual  f closes"),
        rows,
    };
    frame.render_widget(Clear, area);
    frame.render_widget(
        Paragraph::new(frame_box.lines(width).join("\n")).style(Style::default().fg(Color::White)),
        area,
    );
}
X
)
(define bar-text (file->string bar-path))
(define state-text (file->string state-path))
(define draw-text (file->string draw-path))
(cond
  [(string-contains? bar-text "toggle_full_input") (printf "already patched\n")]
  [else
   (define s1 (once state-text "\" \" => crate::bar_view::toggle_menu()," "\" \" => crate::bar_view::toggle_menu(),\n                        \"f\" => crate::bar_view::toggle_full_input()," "input_state.rs space key"))
   (define s2 (once s1 "        self.mode = Mode::Insert;\n        self.text.push_str(cleaned.trim_end_matches(\"\\n\"));\n        self.cursor = None;"
                    "        self.mode = Mode::Insert;\n        self.text.push_str(cleaned.trim_end_matches(\"\\n\"));\n        self.cursor = None;\n        if self.text.chars().count() > 400 || self.text.lines().count() > 6 {\n            crate::bar_view::open_full_input();\n        }" "input_state.rs paste"))
   (define d1 (once draw-text "    let input_box = BoxFrame {\n        title: input_title(state, title),"
                    "    let keep_chars = width.saturating_sub(4);\n    let row_count = row.chars().count();\n    if row_count > keep_chars && keep_chars > 1 {\n        let tail: String = row.chars().skip(row_count - keep_chars + 1).collect();\n        row = format!(\"\\u{2026}{}\", tail);\n    }\n    let input_box = BoxFrame {\n        title: input_title(state, title)," "screen_draw.rs input_box"))
   (define d2 (once d1 "            \"input\",\n" "            \"input  f full screen edit\",\n" "screen_draw.rs visual title"))
   (define d3 (once d2 "    crate::bar_view::draw_menu(frame, state, area);" "    crate::bar_view::draw_menu(frame, state, area);\n    crate::bar_view::draw_full_input(frame, state, full_area);" "screen_draw.rs draw_menu"))
   (display-to-file (string-append bar-text bar-add) bar-path #:exists (quote truncate))
   (display-to-file s2 state-path #:exists (quote truncate))
   (display-to-file d3 draw-path #:exists (quote truncate))
   (display-to-file "\ntodo: full input view: f in visual mode toggles a full screen editor for the input box inside the screen pane; it does not cover the aiutm bars yet (needs the screen to tell aiutm to toggle focus, for example through a private OSC sequence caught in pane-grid.rkt); the cursor is always at the end, no cursor movement or editing in the middle\n" todo-path #:exists (quote append))
   (display-to-file "\n- Input box: long text shows its tail with the cursor; f in visual mode opens the full screen input view (opens by itself for a big paste), f again closes it.\n" readme-path #:exists (quote append))
   (define start (file->string starting-path))
   (display-to-file (string-append "- Full input view 2026-11-07: Shape: cursor not visible after a big paste and no way to see the full command; input box shows the tail, f toggles full screen input view, big paste opens it; aiutm cover not done (todo); NEXT STEP: Shape tests, then step 1 daily driver (read ~/.config/nushell).\n" start) starting-path #:exists (quote truncate))])
