    use super::*;

    fn the_lines() -> Vec<String> {
        vec![
            "the first line".to_string(),
            "the second word here".to_string(),
            "the third".to_string(),
        ]
    }

    #[test]
    fn the_point_moves_over_the_visible_text() {
        let lines = the_lines();
        let mut selection = Selection::new();
        selection.right(&lines);
        selection.right(&lines);
        assert_eq!(selection.point, (0, 2));
        selection.down(&lines);
        assert_eq!(selection.point, (1, 2));
        selection.left(&lines);
        assert_eq!(selection.point, (1, 1));
        selection.up(&lines);
        assert_eq!(selection.point, (0, 1));
    }

    #[test]
    fn the_point_moves_by_word() {
        let lines = the_lines();
        let mut selection = Selection::new();
        selection.word_right(&lines);
        assert_eq!(selection.point, (0, 4));
        selection.word_left(&lines);
        assert_eq!(selection.point, (0, 0));
    }

    #[test]
    fn the_region_runs_from_the_mark_to_the_point() {
        let lines = the_lines();
        let mut selection = Selection::new();
        selection.right(&lines);
        selection.right(&lines);
        selection.set_mark();
        selection.down(&lines);
        selection.right(&lines);
        selection.right(&lines);
        assert_eq!(selection.region(&lines), "e first line\nthe ");
    }

    #[test]
    fn the_region_runs_backwards_too() {
        let lines = the_lines();
        let mut selection = Selection::new();
        selection.right(&lines);
        selection.right(&lines);
        selection.set_mark();
        selection.left(&lines);
        selection.left(&lines);
        assert_eq!(selection.region(&lines), "th");
    }

    #[test]
    fn the_marks_are_a_ring() {
        let lines = the_lines();
        let mut selection = Selection::new();
        selection.right(&lines);
        selection.set_mark();
        selection.right(&lines);
        selection.set_mark();
        assert_eq!(selection.mark(), Some((0, 2)));
        selection.pop_mark();
        assert_eq!(selection.mark(), Some((0, 1)));
        selection.pop_mark();
        assert_eq!(selection.mark(), None);
    }

    #[test]
    fn without_a_mark_there_is_no_region() {
        let lines = the_lines();
        let selection = Selection::new();
        assert_eq!(selection.region(&lines), "");
    }

    #[test]
    fn the_marked_lines_show_the_region_in_reverse_video() {
        let lines = the_lines();
        let mut selection = Selection::new();
        selection.right(&lines);
        selection.set_mark();
        selection.right(&lines);
        let marked = selection.marked(&lines);
        assert!(marked[0].contains("\x1b[7m"), "the region is marked: {:?}", marked);
        assert!(marked[1].contains("\x1b[7m") == false, "the other lines are not: {:?}", marked);
    }
