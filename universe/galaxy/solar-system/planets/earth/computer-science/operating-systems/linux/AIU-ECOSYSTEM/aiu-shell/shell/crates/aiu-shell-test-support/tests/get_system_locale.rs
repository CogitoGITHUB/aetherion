#![cfg(debug_assertions)]

use aiu_shell_test_support::locale_override::with_locale_override;
use aiu_shell_utils::get_system_locale;
use num_format::Grouping;

#[test]
fn test_get_system_locale_en() {
    let locale = with_locale_override("en_US.UTF-8", get_system_locale);

    assert_eq!(locale.name(), "en");
    assert_eq!(locale.grouping(), Grouping::Standard)
}

#[test]
fn test_get_system_locale_de() {
    let locale = with_locale_override("de_DE.UTF-8", get_system_locale);

    assert_eq!(locale.name(), "de");
    assert_eq!(locale.grouping(), Grouping::Standard)
}
