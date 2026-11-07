use aiu_shell_history_client::settings::Tmux;
use aiu_shell_history_dotfiles::store::{AliasStore, var::VarStore};
use eyre::Result;

fn print_tmux_config(tmux: &Tmux) {
    if tmux.enabled {
        println!("export AIU_SHELL_HISTORY_TMUX_POPUP_WIDTH='{}'", tmux.width);
        println!("export AIU_SHELL_HISTORY_TMUX_POPUP_HEIGHT='{}'", tmux.height);
    } else {
        println!("export AIU_SHELL_HISTORY_TMUX_POPUP=false");
    }
}

pub fn init_static(disable_up_arrow: bool, disable_ctrl_r: bool, disable_ai: bool, tmux: &Tmux) {
    let base = include_str!("../../../shell/aiu-shell-history.zsh");

    print_tmux_config(tmux);
    println!("{base}");

    if std::env::var("AIU_SHELL_HISTORY_NOBIND").is_err() {
        const BIND_CTRL_R: &str = r"bindkey -M emacs '^r' aiu-shell-history-search
bindkey -M viins '^r' aiu_shell_history-search-viins
bindkey -M vicmd '/' aiu_shell_history-search";

        const BIND_UP_ARROW: &str = r"bindkey -M emacs '^[[A' aiu-shell-history-up-search
bindkey -M vicmd '^[[A' aiu_shell_history-up-search-vicmd
bindkey -M viins '^[[A' aiu_shell_history-up-search-viins
bindkey -M emacs '^[OA' aiu_shell_history-up-search
bindkey -M vicmd '^[OA' aiu_shell_history-up-search-vicmd
bindkey -M viins '^[OA' aiu_shell_history-up-search-viins
bindkey -M vicmd 'k' aiu_shell_history-up-search-vicmd";

        if !disable_ctrl_r {
            println!("{BIND_CTRL_R}");
        }
        if !disable_up_arrow {
            println!("{BIND_UP_ARROW}");
        }

        #[cfg(feature = "ai")]
        if !disable_ai {
            let bind_ai = aiu_shell_history_ai::commands::init::generate_zsh_integration();

            println!("{bind_ai}");
        }
    }
}

pub async fn init(
    aliases: AliasStore,
    vars: VarStore,
    disable_up_arrow: bool,
    disable_ctrl_r: bool,
    disable_ai: bool,
    tmux: &Tmux,
) -> Result<()> {
    init_static(disable_up_arrow, disable_ctrl_r, disable_ai, tmux);

    let aliases = aiu_shell_history_dotfiles::shell::zsh::alias_config(&aliases).await;
    let vars = aiu_shell_history_dotfiles::shell::zsh::var_config(&vars).await;

    println!("{aliases}");
    println!("{vars}");

    Ok(())
}
