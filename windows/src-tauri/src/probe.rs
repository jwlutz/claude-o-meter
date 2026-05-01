use crate::cookies::read_claude_ai_cookies;
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
            ..Default::default()
        },
    }
}

fn probe_inner() -> Result<UsageSnapshot, String> {
    let cookies = read_claude_ai_cookies()?;
    if !cookies.contains_key("sessionKey") {
        return Err("no_session".into());
    }

    let (org_id, plan_tier) = read_org_info()?;

    let url = format!("https://claude.ai/api/organizations/{}/usage", org_id);
    let cookie_header = cookies
        .iter()
        .map(|(k, v)| format!("{k}={v}"))
        .collect::<Vec<_>>()
        .join("; ");

    let client = reqwest::blocking::Client::builder()
        .timeout(std::time::Duration::from_secs(12))
        .build()
        .map_err(|e| format!("client:{e}"))?;

    let resp = client
        .get(&url)
        .header("Cookie", cookie_header)
        .header("User-Agent", USER_AGENT)
        .header("Accept", "application/json, text/plain, */*")
        .header("Origin", "https://claude.ai")
        .header("Referer", "https://claude.ai/")
        .header("Sec-Fetch-Dest", "empty")
        .header("Sec-Fetch-Mode", "cors")
        .header("Sec-Fetch-Site", "same-origin")
        .send()
        .map_err(|e| format!("network:{e}"))?;

    let status = resp.status();
    let body = resp.text().map_err(|e| format!("body:{e}"))?;
    if status.as_u16() == 403 { return Err("http_403".into()); }
    if !status.is_success()   { return Err(format!("http_{}", status.as_u16())); }

    let parsed: UsageResponse = serde_json::from_str(&body)
        .map_err(|e| format!("parse:{e}"))?;

    Ok(UsageSnapshot {
        plan_tier,
        five_hour_pct: parsed.five_hour.utilization,
        five_hour_reset: parse_iso(&parsed.five_hour.resets_at),
        weekly_pct: parsed.seven_day.utilization,
        weekly_reset: parse_iso(&parsed.seven_day.resets_at),
        weekly_sonnet_pct: parsed.seven_day_sonnet.as_ref().map(|w| w.utilization),
        weekly_opus_pct:   parsed.seven_day_opus.as_ref().map(|w| w.utilization),
        last_error: None,
    })
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
    if raw.starts_with("local_state_read") || raw.starts_with("local_state_no") {
        return "Couldn't read Claude.app keys. Install/run Claude.app once.".into();
    }
    if raw.starts_with("dpapi") {
        return "DPAPI failed — log into the same Windows user that runs Claude.app.".into();
    }
    if raw.starts_with("no_cookies") {
        return "Claude.app cookies missing. Install/run Claude.app once.".into();
    }
    if raw.starts_with("no_session") {
        return "Not signed in to Claude.app — sign in there, then refresh.".into();
    }
    if raw.starts_with("no_org") {
        return "Couldn't read your org from %USERPROFILE%\\.claude.json — sign in to Claude Code first.".into();
    }
    if raw == "http_403" {
        return "Anthropic blocked the request (cookies expired). Reopen Claude.app, then retry.".into();
    }
    raw.to_string()
}
