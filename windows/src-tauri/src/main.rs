// Windows tray-only entry point. No main window is ever shown — the icon
// in the system tray (notification area at the right edge of the taskbar)
// is the entire UI. Hover for the tooltip; right-click for Refresh / Quit.

#![cfg_attr(all(not(debug_assertions), windows), windows_subsystem = "windows")]

mod cookies;
mod icon_render;
mod probe;
mod types;

use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use tauri::{
    image::Image,
    menu::{Menu, MenuItem},
    tray::{TrayIconBuilder, TrayIconEvent},
    Manager,
};
use tauri_plugin_autostart::{MacosLauncher, ManagerExt};

use crate::types::UsageSnapshot;

const PROBE_INTERVAL: Duration = Duration::from_secs(60);

fn main() {
    let snapshot = Arc::new(Mutex::new(UsageSnapshot::default()));

    tauri::Builder::default()
        .plugin(tauri_plugin_autostart::Builder::new()
            .args(Vec::<&str>::new())
            .build())
        .setup({
            let snapshot = snapshot.clone();
            move |app| {
                // Register at login on first run.
                let _ = app.autolaunch().enable();

                // Tray menu: Refresh, Quit
                let refresh = MenuItem::with_id(app, "refresh", "Refresh now", true, None::<&str>)?;
                let quit    = MenuItem::with_id(app, "quit",    "Quit",        true, None::<&str>)?;
                let menu    = Menu::with_items(app, &[&refresh, &quit])?;

                let initial_icon = make_image(0.0);
                let tray = TrayIconBuilder::with_id("main")
                    .icon(initial_icon)
                    .menu(&menu)
                    .tooltip("Claude-o-Meter — starting…")
                    .on_menu_event({
                        let snapshot = snapshot.clone();
                        move |app, event| {
                            match event.id.as_ref() {
                                "refresh" => kick_probe(snapshot.clone(), app.clone()),
                                "quit" => app.exit(0),
                                _ => {}
                            }
                        }
                    })
                    .on_tray_icon_event({
                        let snapshot = snapshot.clone();
                        move |tray, event| {
                            if let TrayIconEvent::Click { .. } = event {
                                kick_probe(snapshot.clone(), tray.app_handle().clone());
                            }
                        }
                    })
                    .build(app)?;

                // Background probe loop
                let snapshot_thread = snapshot.clone();
                let app_handle = app.handle().clone();
                thread::spawn(move || {
                    loop {
                        let snap = probe::probe_once();
                        if let Ok(mut s) = snapshot_thread.lock() {
                            *s = snap.clone();
                        }
                        update_tray(&app_handle, &snap);
                        thread::sleep(PROBE_INTERVAL);
                    }
                });

                let _ = tray;
                Ok(())
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

fn kick_probe(snapshot: Arc<Mutex<UsageSnapshot>>, app: tauri::AppHandle) {
    thread::spawn(move || {
        let snap = probe::probe_once();
        if let Ok(mut s) = snapshot.lock() { *s = snap.clone(); }
        update_tray(&app, &snap);
    });
}

fn update_tray(app: &tauri::AppHandle, snap: &UsageSnapshot) {
    if let Some(tray) = app.tray_by_id("main") {
        let fraction = (snap.five_hour_pct / 100.0).clamp(0.0, 1.0);
        let _ = tray.set_icon(Some(make_image(fraction)));
        let _ = tray.set_tooltip(Some(icon_render::tooltip(snap)));
    }
}

fn make_image(fraction: f64) -> Image<'static> {
    let (w, h) = icon_render::icon_size();
    let rgba = icon_render::render_rgba(fraction);
    Image::new_owned(rgba, w, h)
}
