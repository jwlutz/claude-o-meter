// Tiny 5x7 bitmap font for tray-icon countdown text. We only need digits
// 0-9 plus 'h', 'm', 'd', and space. Each glyph is encoded as 7 rows of a
// 5-bit pattern (bit 4 = leftmost column).

const fn r(b: u8) -> u8 { b }

type Glyph = [u8; 7];

const G_0: Glyph = [r(0b01110), r(0b10001), r(0b10011), r(0b10101), r(0b11001), r(0b10001), r(0b01110)];
const G_1: Glyph = [r(0b00100), r(0b01100), r(0b00100), r(0b00100), r(0b00100), r(0b00100), r(0b01110)];
const G_2: Glyph = [r(0b01110), r(0b10001), r(0b00001), r(0b00010), r(0b00100), r(0b01000), r(0b11111)];
const G_3: Glyph = [r(0b11110), r(0b00001), r(0b00001), r(0b01110), r(0b00001), r(0b00001), r(0b11110)];
const G_4: Glyph = [r(0b00010), r(0b00110), r(0b01010), r(0b10010), r(0b11111), r(0b00010), r(0b00010)];
const G_5: Glyph = [r(0b11111), r(0b10000), r(0b11110), r(0b00001), r(0b00001), r(0b10001), r(0b01110)];
const G_6: Glyph = [r(0b00110), r(0b01000), r(0b10000), r(0b11110), r(0b10001), r(0b10001), r(0b01110)];
const G_7: Glyph = [r(0b11111), r(0b00001), r(0b00010), r(0b00100), r(0b01000), r(0b01000), r(0b01000)];
const G_8: Glyph = [r(0b01110), r(0b10001), r(0b10001), r(0b01110), r(0b10001), r(0b10001), r(0b01110)];
const G_9: Glyph = [r(0b01110), r(0b10001), r(0b10001), r(0b01111), r(0b00001), r(0b00010), r(0b01100)];
const G_H: Glyph = [r(0b10000), r(0b10000), r(0b10000), r(0b11110), r(0b10001), r(0b10001), r(0b10001)];
const G_M: Glyph = [r(0b00000), r(0b00000), r(0b11010), r(0b10101), r(0b10101), r(0b10101), r(0b10101)];
const G_D: Glyph = [r(0b00001), r(0b00001), r(0b00001), r(0b01111), r(0b10001), r(0b10001), r(0b01111)];
const G_SP: Glyph = [0; 7];

pub const GLYPH_W: u32 = 5;
pub const GLYPH_H: u32 = 7;
const GLYPH_GAP: u32 = 1;

fn glyph_for(c: char) -> Option<&'static Glyph> {
    Some(match c {
        '0' => &G_0, '1' => &G_1, '2' => &G_2, '3' => &G_3, '4' => &G_4,
        '5' => &G_5, '6' => &G_6, '7' => &G_7, '8' => &G_8, '9' => &G_9,
        'h' | 'H' => &G_H,
        'm' | 'M' => &G_M,
        'd' | 'D' => &G_D,
        ' ' => &G_SP,
        _ => return None,
    })
}

/// Width in pixels of the rendered string (including gaps between glyphs,
/// no trailing gap).
pub fn text_width(text: &str) -> u32 {
    let n = text.chars().filter(|c| glyph_for(*c).is_some()).count() as u32;
    if n == 0 { 0 } else { n * GLYPH_W + (n - 1) * GLYPH_GAP }
}

/// Stamp text into an RGBA buffer of size (buf_w, buf_h) at top-left
/// (x0, y0), in the given color. Pixels with bit set are stamped; others
/// are left untouched.
pub fn draw_text(
    buf: &mut [u8],
    buf_w: u32,
    buf_h: u32,
    x0: u32,
    y0: u32,
    text: &str,
    color: (u8, u8, u8, u8),
) {
    let mut x = x0;
    for ch in text.chars() {
        let Some(glyph) = glyph_for(ch) else { continue };
        for (row, bits) in glyph.iter().enumerate() {
            for col in 0..GLYPH_W {
                let bit_set = (bits >> (GLYPH_W - 1 - col)) & 1 == 1;
                if !bit_set { continue; }
                let px = x + col;
                let py = y0 + row as u32;
                if px >= buf_w || py >= buf_h { continue; }
                let i = ((py * buf_w + px) * 4) as usize;
                buf[i]     = color.0;
                buf[i + 1] = color.1;
                buf[i + 2] = color.2;
                buf[i + 3] = color.3;
            }
        }
        x += GLYPH_W + GLYPH_GAP;
    }
}
