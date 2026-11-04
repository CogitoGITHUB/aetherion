use crate::*;

/// Fields are the story of one record: what happened, who did it, why, and
/// how. The identity and timing fields are added by the session itself.
pub(crate) struct Fields<'a> {
    pub(crate) kind: &'a str,
    pub(crate) who: &'a str,
    pub(crate) what: &'a str,
    pub(crate) why: &'a str,
    pub(crate) how: &'a str,
    pub(crate) inputs: Value,
    pub(crate) outputs: Value,
    pub(crate) result: Value,
}

