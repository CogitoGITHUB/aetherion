use eyre::Result;

pub async fn run() -> Result<()> {
    aiu_shell_history_client::logout::logout().await
}
