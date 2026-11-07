use aiu_shell_protocol::{Span, engine::StateWorkingSet};
use quickcheck_macros::quickcheck;

#[quickcheck]
fn quickcheck_parse(data: String) -> bool {
    let (tokens, err) = aiu_shell_parser::lex(data.as_bytes(), 0, b"", b"", true);

    if err.is_none() {
        let context = crate::create_default_context();
        {
            let mut working_set = StateWorkingSet::new(&context);
            let _ = working_set.add_file("quickcheck", data.as_bytes());

            let _ = aiu_shell_parser::parse_block(
                &mut working_set,
                &tokens,
                Span::new(0, 0),
                false,
                false,
                None,
            );
        }
    }
    true
}
