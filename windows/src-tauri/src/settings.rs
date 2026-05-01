// Tiny on-disk settings for the tray app — stored next to the binary's
// AppData folder. Currently just one toggle: whether to render the 5-hour
// countdown into the tray icon next to the burst.

use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::sync::{Mutex, OnceLock};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Settings {
    pub show_countdown: bool,
}

impl Default for Settings {
    fn default() -> Self {
        Self { show_countdown: false }
    }
}

static SETTINGS: OnceLock<Mutex<Settings>> = OnceLock::new();

fn cell() -> &'static Mutex<Settings> {
    SETTINGS.get_or_init(|| Mutex::new(load()))
}

fn settings_path() -> Option<PathBuf> {
    let appdata = std::env::var("APPDATA").ok()?;
    let dir = PathBuf::from(appdata).join("claude-o-meter");
    let _ = std::fs::create_dir_all(&dir);
    Some(dir.join("settings.json"))
}

fn load() -> Settings {
    let path = match settings_path() { Some(p) => p, None => return Settings::default() };
    match std::fs::read_to_string(&path) {
        Ok(raw) => serde_json::from_str(&raw).unwrap_or_default(),
        Err(_) => Settings::default(),
    }
}

pub fn get() -> Settings {
    cell().lock().map(|s| s.clone()).unwrap_or_default()
}

pub fn set_show_countdown(value: bool) {
    if let Ok(mut s) = cell().lock() {
        s.show_countdown = value;
        if let Some(path) = settings_path() {
            let _ = std::fs::write(&path, serde_json::to_string_pretty(&*s).unwrap());
        }
    }
}
