use super::{config_update_string_enum, prelude::*};

use crate::{self as aiu_shell_protocol};

/// The largest time unit used when formatting durations for display.
///
/// When set to a smaller unit, durations that would previously show weeks
/// will instead show the equivalent number of days, hours, etc.
#[derive(
    Clone, Copy, Default, Debug, IntoValue, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize,
)]
pub enum DurationMaxUnit {
    #[default]
    #[aiu_shell_value(rename = "wk")]
    Week,
    #[aiu_shell_value(rename = "day")]
    Day,
    #[aiu_shell_value(rename = "hr")]
    Hour,
    #[aiu_shell_value(rename = "min")]
    Minute,
    #[aiu_shell_value(rename = "sec")]
    Second,
    #[aiu_shell_value(rename = "ms")]
    Millisecond,
    #[aiu_shell_value(rename = "us")]
    Microsecond,
    #[aiu_shell_value(rename = "ns")]
    Nanosecond,
}

impl FromStr for DurationMaxUnit {
    type Err = &'static str;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "wk" => Ok(Self::Week),
            "day" => Ok(Self::Day),
            "hr" => Ok(Self::Hour),
            "min" => Ok(Self::Minute),
            "sec" => Ok(Self::Second),
            "ms" => Ok(Self::Millisecond),
            "us" | "µs" => Ok(Self::Microsecond),
            "ns" => Ok(Self::Nanosecond),
            _ => Err("'wk', 'day', 'hr', 'min', 'sec', 'ms', 'us', 'µs', or 'ns'"),
        }
    }
}

impl UpdateFromValue for DurationMaxUnit {
    fn update(&mut self, value: &Value, path: &mut ConfigPath, errors: &mut ConfigErrors) {
        config_update_string_enum(self, value, path, errors)
    }
}
