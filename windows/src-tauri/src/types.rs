use serde::{Deserialize, Serialize};

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
    pub weekly_sonnet_reset: Option<chrono::DateTime<chrono::Utc>>,
    pub weekly_opus_pct: Option<f64>,
    pub weekly_opus_reset: Option<chrono::DateTime<chrono::Utc>>,
    pub last_error: Option<String>,
    pub generated_at: Option<chrono::DateTime<chrono::Utc>>,
    pub has_data: bool,
}

impl UsageSnapshot {
    /// "4h12m" — same compact format as the Mac side.
    pub fn five_hour_countdown(&self) -> Option<String> {
        countdown_text(self.five_hour_reset)
    }

    /// JSON view for the popover frontend.
    pub fn to_view(&self) -> SnapshotView {
        SnapshotView {
            plan_tier: self.plan_tier.clone(),
            five_hour_pct: self.five_hour_pct,
            five_hour_reset_text: countdown_text(self.five_hour_reset),
            weekly_pct: self.weekly_pct,
            weekly_reset_text: countdown_text(self.weekly_reset),
            weekly_sonnet_pct: self.weekly_sonnet_pct,
            weekly_sonnet_reset_text: countdown_text(self.weekly_sonnet_reset),
            weekly_opus_pct: self.weekly_opus_pct,
            weekly_opus_reset_text: countdown_text(self.weekly_opus_reset),
            last_error: self.last_error.clone(),
            generated_at: self.generated_at.map(|d| d.to_rfc3339()),
            has_data: self.has_data,
        }
    }
}

/// Serialized snapshot sent to the popover webview.
#[derive(Debug, Clone, Serialize)]
pub struct SnapshotView {
    pub plan_tier: String,
    pub five_hour_pct: f64,
    pub five_hour_reset_text: Option<String>,
    pub weekly_pct: f64,
    pub weekly_reset_text: Option<String>,
    pub weekly_sonnet_pct: Option<f64>,
    pub weekly_sonnet_reset_text: Option<String>,
    pub weekly_opus_pct: Option<f64>,
    pub weekly_opus_reset_text: Option<String>,
    pub last_error: Option<String>,
    pub generated_at: Option<String>,
    pub has_data: bool,
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

fn countdown_text(reset: Option<chrono::DateTime<chrono::Utc>>) -> Option<String> {
    let reset = reset?;
    let secs = (reset - chrono::Utc::now()).num_seconds().max(0);
    Some(format_duration(secs))
}
