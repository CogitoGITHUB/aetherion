    use super::*;

    /// two_weighed answers the places of two panes that want one and three.
    fn two_weighed() -> Vec<Rect> {
        rects("row", &[1, 3], 80, 24, 1)
    }

    #[test]
    fn the_weight_divides_the_space() {
        let held = two_weighed();
        assert_eq!(held.len(), 2);
        assert_eq!(held[0].cols, 20);
        assert_eq!(held[1].cols, 60);
    }

    #[test]
    fn the_last_pane_takes_what_is_left() {
        let held = two_weighed();
        assert_eq!(held[0].left, 1);
        assert_eq!(held[1].left, 21);
    }

    #[test]
    fn the_column_direction_stacks_the_panes() {
        let held = rects("column", &[1, 3], 80, 24, 1);
        assert_eq!(held[0].rows, 6);
        assert_eq!(held[1].rows, 18);
        assert_eq!(held[1].top, 7);
    }

    #[test]
    fn a_pane_is_never_too_narrow_to_read() {
        let held = rects("row", &[1, 1], 4, 24, 1);
        assert!(held[0].cols >= MIN_COLS);
        assert!(held[1].cols >= MIN_COLS);
    }
