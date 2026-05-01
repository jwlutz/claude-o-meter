// Windows tray entry point. Tray icon shows the burst with a clockwise
// pie-drain effect; left-click opens a popover window with full usage
// detail; right-click shows a Refresh / Quit menu.

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
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    AppHandle, LogicalSize, Manager, PhysicalPosition, WebviewUrl, WebviewWindowBuilder,
};
use tauri_plugin_autostart::ManagerExt;

use crate::types::{SnapshotView, UsageSnapshot};

const PROBE_INTERVAL: Duration = Duration::from_secs(300); // 5 minutes — endpoint rate-limits
const POPOVER_LABEL: &str = "popover";
const POPOVER_W: f64 = 440.0;
const POPOVER_H: f64 = 420.0;

struct AppState {
    snapshot: Arc<Mutex<UsageSnapshot>>,
}

#[tauri::command]
fn get_snapshot(state: tauri::State<AppState>) -> SnapshotView {
    state.snapshot.lock().map(|s| s.to_view()).unwrap_or_else(|_| {
        UsageSnapshot::default().to_view()
    })
}

#[tauri::command]
fn kick_refresh(state: tauri::State<AppState>, app: AppHandle) {
    let snapshot = state.snapshot.clone();
    thread::spawn(move || {
        let snap = probe::probe_once();
        if let Ok(mut s) = snapshot.lock() { *s = snap.clone(); }
        update_tray(&app, &snap);
    });
}

#[tauri::command]
fn quit_app(app: AppHandle) {
    app.exit(0);
}

#[tauri::command]
fn autostart_is_enabled(app: AppHandle) -> bool {
    app.autolaunch().is_enabled().unwrap_or(false)
}

#[tauri::command]
fn autostart_set(app: AppHandle, enabled: bool) -> Result<bool, String> {
    let manager = app.autolaunch();
    let result = if enabled { manager.enable() } else { manager.disable() };
    result.map_err(|e| e.to_string())?;
    Ok(manager.is_enabled().unwrap_or(enabled))
}

/// Render a single pie-on-burst PNG for the popover rows. Returns base64.
#[tauri::command]
fn render_pie_png(fraction: f64) -> String {
    use base64::{engine::general_purpose::STANDARD as B64, Engine as _};
    let size = 96u32;
    let mut buf = vec![0u8; (size * size * 4) as usize];
    icon_render::render_burst_into(&mut buf, size, size, 0, 0, size, fraction);
    let mut png_bytes: Vec<u8> = Vec::new();
    {
        let mut encoder = png::Encoder::new(&mut png_bytes, size, size);
        encoder.set_color(png::ColorType::Rgba);
        encoder.set_depth(png::BitDepth::Eight);
        if let Ok(mut w) = encoder.write_header() {
            let _ = w.write_image_data(&buf);
        }
    }
    B64.encode(&png_bytes)
}

fn main() {
    let snapshot = Arc::new(Mutex::new(UsageSnapshot::default()));

    tauri::Builder::default()
        .plugin(tauri_plugin_autostart::Builder::new()
            .args(Vec::<&str>::new())
            .build())
        .manage(AppState { snapshot: snapshot.clone() })
        .invoke_handler(tauri::generate_handler![
            get_snapshot, kick_refresh, quit_app, render_pie_png,
            autostart_is_enabled, autostart_set,
        ])
        .setup({
            let snapshot = snapshot.clone();
            move |app| {
                // Build the popover webview window once, hidden. Show/hide on tray click.
                let popover = WebviewWindowBuilder::new(
                    app,
                    POPOVER_LABEL,
                    WebviewUrl::App("index.html".into()),
                )
                .title("Claude-o-Meter")
                .inner_size(POPOVER_W, POPOVER_H)
                .resizable(false)
                .decorations(false)
                .always_on_top(true)
                .skip_taskbar(true)
                .visible(false)
                .focused(false)
                .build()?;

                // Hide on focus loss so it behaves like a popover.
                let popover_handle = popover.clone();
                popover.on_window_event(move |event| {
                    if let tauri::WindowEvent::Focused(false) = event {
                        let _ = popover_handle.hide();
                    }
                });

                // Right-click menu: Refresh / Quit
                let refresh = MenuItem::with_id(app, "refresh", "Refresh now", true, None::<&str>)?;
                let quit    = MenuItem::with_id(app, "quit",    "Quit",        true, None::<&str>)?;
                let menu    = Menu::with_items(app, &[&refresh, &quit])?;

                let initial_icon = make_image(0.0);
                let _tray = TrayIconBuilder::with_id("main")
                    .icon(initial_icon)
                    .menu(&menu)
                    .menu_on_left_click(false)
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
                    .on_tray_icon_event(move |tray, event| {
                        if let TrayIconEvent::Click {
                            button: MouseButton::Left,
                            button_state: MouseButtonState::Up,
                            position,
                            rect,
                            ..
                        } = event {
                            toggle_popover(tray.app_handle(), position, rect);
                        }
                    })
                    .build(app)?;

                // Background probe loop
                let snapshot_thread = snapshot.clone();
                let app_handle = app.handle().clone();
                thread::spawn(move || {
                    loop {
                        let snap = probe::probe_once();
                        if let Ok(mut s) = snapshot_thread.lock() { *s = snap.clone(); }
                        update_tray(&app_handle, &snap);
                        thread::sleep(PROBE_INTERVAL);
                    }
                });

                Ok(())
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

fn kick_probe(snapshot: Arc<Mutex<UsageSnapshot>>, app: AppHandle) {
    thread::spawn(move || {
        let snap = probe::probe_once();
        if let Ok(mut s) = snapshot.lock() { *s = snap.clone(); }
        update_tray(&app, &snap);
    });
}

fn update_tray(app: &AppHandle, snap: &UsageSnapshot) {
    if let Some(tray) = app.tray_by_id("main") {
        let fraction = (snap.five_hour_pct / 100.0).clamp(0.0, 1.0);
        let (w, h) = icon_render::icon_size();
        let rgba = icon_render::render_rgba(fraction);
        let _ = tray.set_icon(Some(Image::new_owned(rgba, w, h)));
        let _ = tray.set_tooltip(Some(icon_render::tooltip(snap)));
    }
}

fn make_image(fraction: f64) -> Image<'static> {
    let (w, h) = icon_render::icon_size();
    let rgba = icon_render::render_rgba(fraction);
    Image::new_owned(rgba, w, h)
}

fn toggle_popover(app: &AppHandle, click: tauri::PhysicalPosition<f64>, tray_rect: tauri::Rect) {
    let Some(window) = app.get_webview_window(POPOVER_LABEL) else { return };

    if window.is_visible().unwrap_or(false) {
        let _ = window.hide();
        return;
    }

    // Anchor the popover above the tray (Windows taskbar is bottom by default,
    // but support top/left/right by snapping toward the click position and
    // clamping inside the monitor).
    if let Ok(Some(monitor)) = window.current_monitor().or_else(|_| window.primary_monitor()) {
        let scale = monitor.scale_factor();
        let mon_pos = monitor.position();
        let mon_size = monitor.size();
        let mon_x = mon_pos.x as f64;
        let mon_y = mon_pos.y as f64;
        let mon_w = mon_size.width as f64;
        let mon_h = mon_size.height as f64;

        let win_w = POPOVER_W * scale;
        let win_h = POPOVER_H * scale;

        // Center horizontally on the click, then clamp into the monitor with
        // an 8px gap from the edges.
        let gap = 8.0 * scale;
        let mut x = click.x - win_w / 2.0;
        x = x.max(mon_x + gap).min(mon_x + mon_w - win_w - gap);

        // Place above tray if click is in the bottom half of the screen,
        // otherwise below.
        let tray_phys = tray_rect.position.to_physical::<f64>(scale);
        let tray_size_phys = tray_rect.size.to_physical::<f64>(scale);
        let tray_top = tray_phys.y;
        let tray_bottom = tray_top + tray_size_phys.height;
        let mut y = if click.y > mon_y + mon_h / 2.0 {
            tray_top - win_h - gap
        } else {
            tray_bottom + gap
        };
        y = y.max(mon_y + gap).min(mon_y + mon_h - win_h - gap);

        let _ = window.set_position(PhysicalPosition::new(x, y));
        let _ = window.set_size(LogicalSize::new(POPOVER_W, POPOVER_H));
    }

    let _ = window.show();
    let _ = window.set_focus();
}
