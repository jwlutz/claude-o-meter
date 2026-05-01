// Render the tray icon — Claude burst with a clockwise pie-chart drain
// effect. Mirrors the macOS look exactly, just done in tiny-skia instead
// of CoreGraphics.

use image::ImageReader;
use std::io::Cursor;
use tiny_skia::{Color, FillRule, Paint, PathBuilder, Pixmap, Rect, Transform};

/// Embedded burst PNG. We bundle the same asset Anthropic's tray uses on
/// macOS — alpha-channel template, black on transparent.
const BURST_PNG: &[u8] = include_bytes!("../icons/burst.png");

const SIZE: u32 = 32; // Windows tray icons are typically 32×32 (or 16×16)

pub struct IconColors {
    pub bright: (u8, u8, u8, u8),
    pub drained: (u8, u8, u8, u8),
}
impl Default for IconColors {
    fn default() -> Self {
        Self {
            bright:  (237, 115, 71, 255),  // ~ rgb(0.93, 0.45, 0.28)
            drained: (140, 140, 140, 76),  // ~ rgb(0.55) at alpha 0.30
        }
    }
}

/// Returns a `SIZE×SIZE` RGBA8 buffer. `fraction` ∈ [0, 1] is the portion
/// used (so bright orange fills the *remaining* wedge clockwise from 12
/// o'clock; at fraction=0 the whole burst is bright).
pub fn render_rgba(fraction: f64) -> Vec<u8> {
    let used = fraction.clamp(0.0, 1.0);
    let cs = IconColors::default();

    // Decode the burst as a luminance/alpha mask
    let burst = ImageReader::new(Cursor::new(BURST_PNG))
        .with_guessed_format()
        .ok()
        .and_then(|r| r.decode().ok())
        .map(|img| img.to_rgba8());

    let mut pix = Pixmap::new(SIZE, SIZE).expect("pixmap");

    if let Some(burst_img) = burst {
        // Resize to icon size with simple nearest sampling — burst shape
        // is forgiving and tiny-skia doesn't ship a resizer for free.
        let w_src = burst_img.width();
        let h_src = burst_img.height();
        let mut tinted_full = vec![0u8; (SIZE * SIZE * 4) as usize];
        let mut tinted_mask = vec![0u8; (SIZE * SIZE * 4) as usize];

        for y in 0..SIZE {
            for x in 0..SIZE {
                let sx = (x as f64 / SIZE as f64 * w_src as f64) as u32;
                let sy = (y as f64 / SIZE as f64 * h_src as f64) as u32;
                let p = burst_img.get_pixel(sx.min(w_src - 1), sy.min(h_src - 1));
                let alpha = p[3];
                let i = ((y * SIZE + x) * 4) as usize;
                // Drained baseline (always painted)
                tinted_full[i]     = cs.drained.0;
                tinted_full[i + 1] = cs.drained.1;
                tinted_full[i + 2] = cs.drained.2;
                tinted_full[i + 3] = ((alpha as u16 * cs.drained.3 as u16) / 255) as u8;
                // Bright version (will be wedge-clipped)
                tinted_mask[i]     = cs.bright.0;
                tinted_mask[i + 1] = cs.bright.1;
                tinted_mask[i + 2] = cs.bright.2;
                tinted_mask[i + 3] = alpha;
            }
        }

        // Lay down the drained baseline.
        blit_rgba_into(&mut pix, &tinted_full);

        // Determine which pixels are inside the *remaining* wedge.
        // Wedge sweeps clockwise from 12 o'clock.
        let cx = SIZE as f64 / 2.0;
        let cy = SIZE as f64 / 2.0;
        for y in 0..SIZE {
            for x in 0..SIZE {
                let dx = x as f64 + 0.5 - cx;
                let dy = y as f64 + 0.5 - cy;
                // angle from 12 o'clock, going clockwise, in [0, 1)
                let theta = clockwise_from_top(dx, dy);
                let in_used = theta < used;
                if !in_used {
                    let i = ((y * SIZE + x) * 4) as usize;
                    let dst = pix.data_mut();
                    blend_over(dst, i, &tinted_mask, i);
                }
            }
        }
    } else {
        // Fallback: simple ring + pie wedge
        draw_circle(&mut pix, cs.drained);
        if used < 0.999 {
            draw_remaining_wedge(&mut pix, used, cs.bright);
        }
    }

    pix.data().to_vec()
}

fn clockwise_from_top(dx: f64, dy: f64) -> f64 {
    // Angle 0 at 12 o'clock, increasing clockwise to 1 (full revolution).
    // dy is screen-down positive.
    let mut a = (-dx).atan2(-dy); // 0 at top, π at bottom going +x→…
    if a < 0.0 { a += std::f64::consts::TAU; }
    a / std::f64::consts::TAU
}

fn blit_rgba_into(pix: &mut Pixmap, src: &[u8]) {
    let dst = pix.data_mut();
    debug_assert_eq!(dst.len(), src.len());
    dst.copy_from_slice(src);
}

fn blend_over(dst: &mut [u8], di: usize, src: &[u8], si: usize) {
    let sa = src[si + 3] as u32;
    if sa == 0 { return; }
    let inv = 255 - sa;
    for k in 0..3 {
        dst[di + k] = ((src[si + k] as u32 * sa + dst[di + k] as u32 * inv) / 255) as u8;
    }
    dst[di + 3] = (sa + (dst[di + 3] as u32 * inv) / 255) as u8;
}

fn draw_circle(pix: &mut Pixmap, color: (u8, u8, u8, u8)) {
    let mut paint = Paint::default();
    paint.set_color(Color::from_rgba8(color.0, color.1, color.2, color.3));
    paint.anti_alias = true;
    let r = SIZE as f32 / 2.0 - 1.0;
    let mut pb = PathBuilder::new();
    pb.push_circle(SIZE as f32 / 2.0, SIZE as f32 / 2.0, r);
    if let Some(path) = pb.finish() {
        pix.fill_path(&path, &paint, FillRule::Winding, Transform::identity(), None);
    }
}

fn draw_remaining_wedge(pix: &mut Pixmap, used: f64, color: (u8, u8, u8, u8)) {
    let mut paint = Paint::default();
    paint.set_color(Color::from_rgba8(color.0, color.1, color.2, color.3));
    paint.anti_alias = true;
    let cx = SIZE as f32 / 2.0;
    let cy = SIZE as f32 / 2.0;
    let r = SIZE as f32 / 2.0 - 1.0;

    // Approximate arc with line segments (fine enough at 32px)
    let start = (1.0 - used) * std::f64::consts::TAU; // wedge "remaining" portion
    let segments = 96;
    let mut pb = PathBuilder::new();
    pb.move_to(cx, cy);
    for i in 0..=segments {
        let t = i as f64 / segments as f64;
        let a = -std::f64::consts::FRAC_PI_2 + (1.0 - used) * std::f64::consts::TAU * t * 0.0
              + (-std::f64::consts::FRAC_PI_2 + (1.0 - used) * (1.0 - t) * std::f64::consts::TAU);
        let x = cx + r * a.cos() as f32;
        let y = cy + r * a.sin() as f32;
        pb.line_to(x, y);
    }
    let _ = start;
    pb.close();
    if let Some(path) = pb.finish() {
        pix.fill_path(&path, &paint, FillRule::Winding, Transform::identity(), None);
    }
}

pub fn icon_size() -> (u32, u32) {
    (SIZE, SIZE)
}

/// Hover tooltip text: "5h: 24% · 4h12m  /  Week: 19%"
pub fn tooltip(snap: &crate::types::UsageSnapshot) -> String {
    if let Some(err) = &snap.last_error {
        return format!("Claude-o-Meter — {}", err);
    }
    let five = format!("5h: {}%", snap.five_hour_pct.round() as i64);
    let countdown = snap
        .five_hour_countdown()
        .map(|c| format!(" · {}", c))
        .unwrap_or_default();
    let week = format!("Week: {}%", snap.weekly_pct.round() as i64);
    format!("{}{}  /  {}", five, countdown, week)
}

/// Bounds rect helper retained for completeness.
#[allow(dead_code)]
fn bounds() -> Rect {
    Rect::from_xywh(0.0, 0.0, SIZE as f32, SIZE as f32).unwrap()
}
