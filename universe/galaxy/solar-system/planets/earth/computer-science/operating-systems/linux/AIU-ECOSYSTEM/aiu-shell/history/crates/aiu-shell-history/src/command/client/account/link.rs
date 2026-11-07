use eyre::{Result, bail};

use aiu_shell_history_client::settings::Settings;

pub async fn run(settings: &Settings) -> Result<()> {
    let meta = Settings::meta_store().await?;

    let cli_token = meta.session_token().await?;
    let hub_token = meta.hub_session_token().await?;

    let Some(cli_token) = cli_token else {
        bail!("No CLI session found. Please log in first with 'aiu-shell-history login'.");
    };

    let hub_address = settings.active_hub_endpoint().unwrap_or_default();

    if hub_token.is_some() {
        println!("Found both Hub and CLI sessions. Linking accounts...");
    } else {
        println!("Found CLI session but no Hub session. Logging in to Hub first...");

        let session = aiu_shell_history_client::hub::HubAuthSession::start(hub_address.as_ref()).await?;
        println!("Open this URL to authenticate with aiu-shell-history Hub:");
        println!("{}", session.auth_url);

        let token = session
            .wait_for_completion(
                aiu_shell_history_client::hub::DEFAULT_AUTH_TIMEOUT,
                aiu_shell_history_client::hub::DEFAULT_POLL_INTERVAL,
            )
            .await?;

        aiu_shell_history_client::hub::save_session(&token).await?;
        println!("Hub authentication complete.");
    }

    aiu_shell_history_client::hub::link_account(hub_address.as_ref(), &cli_token).await?;
    println!("Successfully linked CLI account to Hub.");

    Ok(())
}
