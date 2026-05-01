use crate::types::{UsageResponse, UsageSnapshot};
use serde_json::Value;

const USER_AGENT: &str = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 \
    (KHTML, like Gecko) Claude/1.4758.0 Chrome/130.0.6723.137 Electron/33.4.11 Safari/537.36";

/// Run one probe. Returns either a populated snapshot or a snapshot with
/// only `last_error` set (so the tray UI can surface what's wrong).
pub fn probe_once() -> UsageSnapshot {
    match probe_inner() {
        Ok(snap) => snap,
        Err(reason) => UsageSnapshot {
            last_error: Some(humanize(&reason)),
            generated_at: Some(chrono::Utc::now()),
            ..Default::default()
        },
    }
}

fn probe_inner() -> Result<UsageSnapshot, String> {
    // Use Claude Code's OAuth bearer token from %USERPROFILE%\.claude\.credentials.json
    // instead of decrypting Chromium cookies (App-Bound v20 encryption on
    // modern Electron makes that path infeasible).
    let mut access_token = read_access_token()?;
    // Plan label comes from subscriptionType in credentials.json (e.g.
    // "max_5x", "pro"). Falls back to organizationRateLimitTier from
    // .claude.json, then "subscription".
    let plan_tier = read_subscription_type()
        .or_else(|| read_org_info().ok().map(|(_, t)| t))
        .unwrap_or_else(|| "subscription".into());

    let url = "https://api.anthropic.com/api/oauth/usage";
    let client = reqwest::blocking::Client::builder()
        .timeout(std::time::Duration::from_secs(12))
        .build()
        .map_err(|e| format!("client:{e}"))?;

    let do_get = |tok: &str| -> Result<reqwest::blocking::Response, String> {
        client
            .get(url)
            .header("Authorization", format!("Bearer {}", tok))
            .header("anthropic-beta", "oauth-2025-04-20")
            .header("Content-Type", "application/json")
            .header("User-Agent", USER_AGENT)
            .header("Accept", "application/json")
            .send()
            .map_err(|e| format!("network:{e}"))
    };

    let mut resp = do_get(&access_token)?;
    if resp.status().as_u16() == 401 {
        // Token expired — refresh and retry once.
        access_token = refresh_tokens()?;
        resp = do_get(&access_token)?;
    }

    let status = resp.status();
    let body = resp.text().map_err(|e| format!("body:{e}"))?;
    if status.as_u16() == 401 || status.as_u16() == 403 {
        return Err(format!("http_{}", status.as_u16()));
    }
    if !status.is_success() { return Err(format!("http_{}", status.as_u16())); }

    let parsed: UsageResponse = serde_json::from_str(&body)
        .map_err(|e| format!("parse:{e}"))?;

    Ok(UsageSnapshot {
        plan_tier,
        five_hour_pct: parsed.five_hour.utilization,
        five_hour_reset: parse_iso(&parsed.five_hour.resets_at),
        weekly_pct: parsed.seven_day.utilization,
        weekly_reset: parse_iso(&parsed.seven_day.resets_at),
        weekly_sonnet_pct: parsed.seven_day_sonnet.as_ref().map(|w| w.utilization),
        weekly_sonnet_reset: parsed.seven_day_sonnet.as_ref().and_then(|w| parse_iso(&w.resets_at)),
        weekly_opus_pct:   parsed.seven_day_opus.as_ref().map(|w| w.utilization),
        weekly_opus_reset: parsed.seven_day_opus.as_ref().and_then(|w| parse_iso(&w.resets_at)),
        last_error: None,
        generated_at: Some(chrono::Utc::now()),
        has_data: true,
    })
}

fn credentials_path() -> Result<std::path::PathBuf, String> {
    let home = std::env::var("USERPROFILE")
        .or_else(|_| std::env::var("HOME"))
        .map_err(|_| "no_home".to_string())?;
    Ok(std::path::PathBuf::from(home).join(".claude").join(".credentials.json"))
}

fn read_credentials() -> Result<Value, String> {
    let path = credentials_path()?;
    let raw = std::fs::read_to_string(&path).map_err(|e| format!("no_credentials:{e}"))?;
    serde_json::from_str(&raw).map_err(|e| format!("credentials_json:{e}"))
}

fn read_access_token() -> Result<String, String> {
    let json = read_credentials()?;
    let token = json
        .get("claudeAiOauth")
        .and_then(|o| o.get("accessToken"))
        .and_then(|v| v.as_str())
        .ok_or_else(|| "no_access_token".to_string())?
        .to_string();
    Ok(token)
}

fn read_subscription_type() -> Option<String> {
    let json = read_credentials().ok()?;
    let oauth = json.get("claudeAiOauth")?;
    // Prefer rateLimitTier (specific, e.g. "default_claude_max_20x") over
    // subscriptionType (generic, e.g. "max"). Falls through to either if
    // only one is present.
    oauth.get("rateLimitTier").and_then(|v| v.as_str()).map(String::from)
        .or_else(|| oauth.get("subscriptionType").and_then(|v| v.as_str()).map(String::from))
}

/// Refresh the OAuth tokens at platform.claude.com and persist back to
/// .credentials.json. Returns the new access token.
fn refresh_tokens() -> Result<String, String> {
    let mut json = read_credentials()?;
    let refresh_token = json
        .get("claudeAiOauth")
        .and_then(|o| o.get("refreshToken"))
        .and_then(|v| v.as_str())
        .ok_or_else(|| "no_refresh_token".to_string())?
        .to_string();

    let client = reqwest::blocking::Client::builder()
        .timeout(std::time::Duration::from_secs(12))
        .build()
        .map_err(|e| format!("client:{e}"))?;

    let form = [
        ("grant_type", "refresh_token"),
        ("refresh_token", refresh_token.as_str()),
        ("client_id", "9d1c250a-e61b-44d9-88ed-5944d1962f5e"),
    ];

    let resp = client
        .post("https://platform.claude.com/v1/oauth/token")
        .header("User-Agent", "claude-cli/1.0.0 (external, cli)")
        .form(&form)
        .send()
        .map_err(|e| format!("refresh_network:{e}"))?;

    if !resp.status().is_success() {
        let code = resp.status().as_u16();
        return Err(format!("refresh_http_{code}"));
    }

    let body: Value = resp.json().map_err(|e| format!("refresh_parse:{e}"))?;
    let new_access = body.get("access_token").and_then(|v| v.as_str())
        .ok_or_else(|| "refresh_no_access".to_string())?.to_string();
    let new_refresh = body.get("refresh_token").and_then(|v| v.as_str())
        .ok_or_else(|| "refresh_no_refresh".to_string())?.to_string();
    let expires_in = body.get("expires_in").and_then(|v| v.as_i64()).unwrap_or(28800);

    let now_ms = chrono::Utc::now().timestamp_millis();
    let oauth = json
        .get_mut("claudeAiOauth")
        .and_then(|v| v.as_object_mut())
        .ok_or_else(|| "credentials_shape".to_string())?;
    oauth.insert("accessToken".into(), Value::String(new_access.clone()));
    oauth.insert("refreshToken".into(), Value::String(new_refresh));
    oauth.insert("expiresAt".into(), Value::Number(serde_json::Number::from(
        now_ms + expires_in * 1000,
    )));

    std::fs::write(credentials_path()?, serde_json::to_string_pretty(&json).unwrap())
        .map_err(|e| format!("creds_write:{e}"))?;

    Ok(new_access)
}

/// Read `organizationUuid` + `organizationRateLimitTier` from
/// `%USERPROFILE%\.claude.json` (where Claude Code on Windows writes it,
/// same as the macOS path under `$HOME`).
fn read_org_info() -> Result<(String, String), String> {
    let home = std::env::var("USERPROFILE")
        .or_else(|_| std::env::var("HOME"))
        .map_err(|_| "no_home".to_string())?;
    let path = std::path::PathBuf::from(home).join(".claude.json");
    let raw = std::fs::read_to_string(&path).map_err(|e| format!("no_org:{e}"))?;
    let json: Value = serde_json::from_str(&raw).map_err(|e| format!("org_json:{e}"))?;
    let oauth = json
        .get("oauthAccount")
        .ok_or_else(|| "no_org".to_string())?;
    let org_id = oauth
        .get("organizationUuid")
        .and_then(|v| v.as_str())
        .ok_or_else(|| "no_org".to_string())?
        .to_string();
    let plan_tier = oauth
        .get("organizationRateLimitTier")
        .and_then(|v| v.as_str())
        .unwrap_or("subscription")
        .to_string();
    Ok((org_id, plan_tier))
}

fn parse_iso(s: &Option<String>) -> Option<chrono::DateTime<chrono::Utc>> {
    s.as_ref()
        .and_then(|s| chrono::DateTime::parse_from_rfc3339(s).ok())
        .map(|dt| dt.with_timezone(&chrono::Utc))
}

fn humanize(raw: &str) -> String {
    if raw.starts_with("no_credentials") {
        return "Claude Code credentials not found. Run `claude` once and sign in.".into();
    }
    if raw.starts_with("no_access_token") {
        return "Claude Code OAuth token missing — re-run `claude` and sign in.".into();
    }
    if raw.starts_with("no_org") {
        return "Couldn't read your org — sign in to Claude Code first.".into();
    }
    if raw == "http_429" {
        return "Rate limited by Anthropic. Updates will resume shortly.".into();
    }
    if raw == "http_401" || raw == "http_403" {
        return "Auth rejected by Anthropic. Token may have expired — run `claude` to refresh.".into();
    }
    raw.to_string()
}
