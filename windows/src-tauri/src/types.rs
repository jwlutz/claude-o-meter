use serde::Deserialize;

/// Shape of the JSON returned by
/// `https://claude.ai/api/organizations/<orgId>/usage`. Fields the API may
/// return null are wrapped in `Option`.
#[derive(Debug, Clone, Deserialize)]
pub struct UsageWindow {
    pub utilization: f64,
    pub resets_at: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct UsageResponse {
    pub five_hour: UsageWindow,
    pub seven_day: UsageWindow,
    pub seven_day_sonnet: Option<UsageWindow>,
    pub seven_day_opus: Option<UsageWindow>,
}

/// Snapshot the tray icon renders from. Probe writes; tray reads.
#[derive(Debug, Clone, Default)]
pub struct UsageSnapshot {
    pub plan_tier: String,
    pub five_hour_pct: f64,
    pub five_hour_reset: Option<chrono::DateTime<chrono::Utc>>,
    pub weekly_pct: f64,
    pub weekly_reset: Option<chrono::DateTime<chrono::Utc>>,
    pub weekly_sonnet_pct: Option<f64>,
    pub weekly_opus_pct: Option<f64>,
    pub last_error: Option<String>,
}

impl UsageSnapshot {
    /// "4h12m" — same compact format as the Mac side.
    pub fn five_hour_countdown(&self) -> Option<String> {
        let reset = self.five_hour_reset?;
        let secs = (reset - chrono::Utc::now()).num_seconds().max(0);
        Some(format_duration(secs))
    }
}

pub fn format_duration(seconds: i64) -> String {
    let h = seconds / 3600;
    let m = (seconds % 3600) / 60;
    if h >= 24 {
        let d = h / 24;
        let rh = h % 24;
        if rh == 0 { format!("{}d", d) } else { format!("{}d{}h", d, rh) }
    } else if h > 0 {
        format!("{}h{}m", h, m)
    } else {
        format!("{}m", m)
    }
}
