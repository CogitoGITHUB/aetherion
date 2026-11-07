use std::path::PathBuf;

use aiu_shell_history_client::{
    encryption,
    record::sqlite_store::SqliteStore,
    settings::{Settings, Tmux},
};
use aiu_shell_history_dotfiles::store::{AliasStore, var::VarStore};
use clap::{Parser, ValueEnum};
use eyre::{Result, WrapErr};

mod bash;
mod fish;
mod powershell;
mod xonsh;
mod zsh;

#[derive(Parser, Debug)]
pub struct Cmd {
    shell: Shell,

    /// Disable the binding of CTRL-R to aiu-shell-history
    #[clap(long)]
    disable_ctrl_r: bool,

    /// Disable the binding of the Up Arrow key to aiu-shell-history
    #[clap(long)]
    disable_up_arrow: bool,

    /// Disable the binding of ? to aiu-shell-history AI
    #[clap(long)]
    disable_ai: bool,
}

#[derive(Clone, Copy, ValueEnum, Debug)]
#[value(rename_all = "lower")]
#[allow(clippy::enum_variant_names, clippy::doc_markdown)]
pub enum Shell {
    /// Zsh setup
    Zsh,
    /// Bash setup
    Bash,
    /// Fish setup
    Fish,
    /// Nu setup
    Nu,
    /// Xonsh setup
    Xonsh,
    /// PowerShell setup
    PowerShell,
}

impl Cmd {
    fn init_nu(&self, _tmux: &Tmux) {
        let full = include_str!("../../shell/aiu-shell-history.nu");

        // TODO: tmux popup for Nu
        println!("{full}");

        if std::env::var("AIU_SHELL_HISTORY_NOBIND").is_err() {
            const BIND_CTRL_R: &str = r"$env.config = (
    $env.config | upsert keybindings (
        $env.config.keybindings
        | append {
            name: aiu_shell_history
            modifier: control
            keycode: char_r
            mode: [emacs, vi_normal, vi_insert]
            event: { send: executehostcommand cmd: (_aiu_shell_history_search_cmd) }
        }
    )
)";
            const BIND_UP_ARROW: &str = r"
$env.config = (
    $env.config | upsert keybindings (
        $env.config.keybindings
        | append {
            name: aiu_shell_history
            modifier: none
            keycode: up
            mode: [emacs, vi_normal, vi_insert]
            event: {
                until: [
                    {send: menuup}
                    {send: executehostcommand cmd: (_aiu_shell_history_search_cmd '--shell-up-key-binding') }
                ]
            }
        }
    )
)
";
            if !self.disable_ctrl_r {
                println!("{BIND_CTRL_R}");
            }
            if !self.disable_up_arrow {
                println!("{BIND_UP_ARROW}");
            }
        }
    }

    fn static_init(&self, settings: &Settings) {
        let tmux = &settings.tmux;

        let disable_ai = self.disable_ai || matches!(settings.ai.enabled, Some(false));

        match self.shell {
            Shell::Zsh => {
                zsh::init_static(self.disable_up_arrow, self.disable_ctrl_r, disable_ai, tmux);
            }
            Shell::Bash => {
                bash::init_static(self.disable_up_arrow, self.disable_ctrl_r, disable_ai, tmux);
            }
            Shell::Fish => {
                fish::init_static(self.disable_up_arrow, self.disable_ctrl_r, disable_ai, tmux);
            }
            Shell::Nu => {
                self.init_nu(tmux);
            }
            Shell::Xonsh => {
                xonsh::init_static(self.disable_up_arrow, self.disable_ctrl_r, tmux);
            }
            Shell::PowerShell => {
                powershell::init_static(self.disable_up_arrow, self.disable_ctrl_r, tmux);
            }
        }
    }

    async fn dotfiles_init(&self, settings: &Settings) -> Result<()> {
        let record_store_path = PathBuf::from(settings.record_store_path.as_str());
        let sqlite_store = SqliteStore::new(record_store_path, settings.local_timeout).await?;

        let encryption_key: [u8; 32] = encryption::load_key(settings)
            .context("could not load encryption key")?
            .into();
        let host_id = Settings::host_id().await?;

        let alias_store = AliasStore::new(sqlite_store.clone(), host_id, encryption_key);
        let var_store = VarStore::new(sqlite_store.clone(), host_id, encryption_key);

        let disable_ai = self.disable_ai || matches!(settings.ai.enabled, Some(false));

        match self.shell {
            Shell::Zsh => {
                zsh::init(
                    alias_store,
                    var_store,
                    self.disable_up_arrow,
                    self.disable_ctrl_r,
                    disable_ai,
                    &settings.tmux,
                )
                .await?;
            }
            Shell::Bash => {
                bash::init(
                    alias_store,
                    var_store,
                    self.disable_up_arrow,
                    self.disable_ctrl_r,
                    disable_ai,
                    &settings.tmux,
                )
                .await?;
            }
            Shell::Fish => {
                fish::init(
                    alias_store,
                    var_store,
                    self.disable_up_arrow,
                    self.disable_ctrl_r,
                    disable_ai,
                    &settings.tmux,
                )
                .await?;
            }
            Shell::Nu => self.init_nu(&settings.tmux),
            Shell::Xonsh => {
                xonsh::init(
                    alias_store,
                    var_store,
                    self.disable_up_arrow,
                    self.disable_ctrl_r,
                    &settings.tmux,
                )
                .await?;
            }
            Shell::PowerShell => {
                powershell::init(
                    alias_store,
                    var_store,
                    self.disable_up_arrow,
                    self.disable_ctrl_r,
                    &settings.tmux,
                )
                .await?;
            }
        }

        Ok(())
    }

    pub async fn run(self, settings: &Settings) -> Result<()> {
        if !settings.paths_ok() {
            eprintln!(
                "aiu-shell-history settings paths are broken. Disabling aiu-shell-history shell hooks. Run `aiu-shell-history doctor` to diagnose."
            );
            return Ok(());
        }

        if settings.dotfiles.enabled {
            self.dotfiles_init(settings).await?;
        } else {
            self.static_init(settings);
        }

        Ok(())
    }
}
