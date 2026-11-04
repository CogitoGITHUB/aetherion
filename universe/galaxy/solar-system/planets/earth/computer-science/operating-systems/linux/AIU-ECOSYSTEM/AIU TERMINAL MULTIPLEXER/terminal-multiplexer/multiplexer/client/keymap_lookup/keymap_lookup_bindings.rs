use super::*;

pub fn bindings(context: Context) -> &'static [Binding] {
    match context {
        Context::Root => ROOT,
        Context::Tabs => TABS,
        Context::Panes => PANES,
        Context::Commands => COMMANDS,
        Context::Sessions => SESSIONS,
        Context::Git => GIT,
        Context::Workspace => WORKSPACE,
        Context::Select => SELECT,
    }
}

