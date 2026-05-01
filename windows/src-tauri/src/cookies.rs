// Decrypt the .claude.ai cookies stored by the Claude desktop app on Windows.
//
// On Windows, Chromium uses AES-256-GCM (not the AES-128-CBC seen on macOS).
// The master AES key is stored in `%APPDATA%\Claude\Local State` as base64
// inside the `os_crypt.encrypted_key` JSON path, with a 5-byte "DPAPI"
// prefix that the rest is DPAPI-encrypted with. Steps:
//
//   1. Read Local State JSON, base64-decode os_crypt.encrypted_key, strip
//      the "DPAPI" prefix.
//   2. Hand the remaining bytes to CryptUnprotectData (Win32 DPAPI) to get
//      the 32-byte AES master key.
//   3. For each cookie row in the Cookies SQLite, the encrypted_value blob
//      starts with "v10": then 12 bytes nonce, then ciphertext+16-byte tag.
//      Decrypt with AES-256-GCM to recover the plaintext cookie value.

#[cfg(windows)]
mod windows_impl {
    use aes_gcm::{aead::Aead, Aes256Gcm, Key, KeyInit, Nonce};
    use base64::{engine::general_purpose::STANDARD as B64, Engine as _};
    use serde_json::Value;
    use std::path::PathBuf;
    use windows::Win32::Security::Cryptography::{
        CryptUnprotectData, CRYPT_INTEGER_BLOB,
    };

    pub fn local_state_path() -> PathBuf {
        let appdata = std::env::var("APPDATA").unwrap_or_default();
        PathBuf::from(appdata).join("Claude").join("Local State")
    }

    pub fn cookies_db_path() -> PathBuf {
        let appdata = std::env::var("APPDATA").unwrap_or_default();
        PathBuf::from(appdata).join("Claude").join("Network").join("Cookies")
    }

    pub fn read_master_key() -> Result<[u8; 32], String> {
        let raw = std::fs::read_to_string(local_state_path())
            .map_err(|e| format!("local_state_read:{e}"))?;
        let json: Value = serde_json::from_str(&raw).map_err(|e| format!("local_state_json:{e}"))?;
        let b64 = json["os_crypt"]["encrypted_key"]
            .as_str()
            .ok_or_else(|| "local_state_no_key".to_string())?;
        let mut blob = B64.decode(b64).map_err(|e| format!("local_state_b64:{e}"))?;
        if !blob.starts_with(b"DPAPI") {
            return Err("local_state_no_dpapi_prefix".into());
        }
        blob.drain(..5);

        // Call CryptUnprotectData via the windows crate.
        let mut input = CRYPT_INTEGER_BLOB {
            cbData: blob.len() as u32,
            pbData: blob.as_mut_ptr(),
        };
        let mut output = CRYPT_INTEGER_BLOB::default();

        unsafe {
            CryptUnprotectData(&input, None, None, None, None, 0, &mut output)
                .map_err(|e| format!("dpapi:{e}"))?;
        }

        if output.cbData != 32 {
            return Err(format!("dpapi_unexpected_len:{}", output.cbData));
        }
        let slice = unsafe { std::slice::from_raw_parts(output.pbData, output.cbData as usize) };
        let mut key = [0u8; 32];
        key.copy_from_slice(slice);

        // Free the buffer Win32 allocated for us.
        unsafe {
            let _ = windows::Win32::System::Memory::LocalFree(
                Some(windows::Win32::Foundation::HLOCAL(output.pbData as *mut _)),
            );
        }
        // Avoid unused-mut on input
        let _ = &mut input;

        Ok(key)
    }

    pub fn decrypt_cookie(blob: &[u8], key: &[u8; 32]) -> Option<String> {
        if !blob.starts_with(b"v10") || blob.len() < 3 + 12 + 16 {
            return None;
        }
        let nonce = Nonce::from_slice(&blob[3..15]);
        let ciphertext = &blob[15..];
        let cipher = Aes256Gcm::new(Key::<Aes256Gcm>::from_slice(key));
        let plain = cipher.decrypt(nonce, ciphertext).ok()?;
        String::from_utf8(plain).ok()
    }

    pub fn read_claude_ai_cookies() -> Result<std::collections::HashMap<String, String>, String> {
        let key = read_master_key()?;
        let src = cookies_db_path();
        if !src.exists() {
            return Err("no_cookies_db".into());
        }

        // Copy to a temp location so the live SQLite isn't locked by the app.
        let tmp = std::env::temp_dir().join(format!(
            "claude-o-meter-cookies-{}.db",
            std::process::id()
        ));
        std::fs::copy(&src, &tmp).map_err(|e| format!("cookies_copy:{e}"))?;

        let conn = rusqlite::Connection::open(&tmp).map_err(|e| format!("cookies_open:{e}"))?;
        let mut stmt = conn
            .prepare("SELECT name, encrypted_value FROM cookies WHERE host_key LIKE '%claude.ai%'")
            .map_err(|e| format!("cookies_prepare:{e}"))?;
        let mut rows = stmt
            .query([])
            .map_err(|e| format!("cookies_query:{e}"))?;

        let mut out = std::collections::HashMap::new();
        while let Ok(Some(row)) = rows.next() {
            let name: String = match row.get(0) { Ok(v) => v, _ => continue };
            let blob: Vec<u8> = match row.get(1) { Ok(v) => v, _ => continue };
            if let Some(v) = decrypt_cookie(&blob, &key) {
                out.insert(name, v);
            }
        }
        drop(stmt);
        drop(conn);
        let _ = std::fs::remove_file(&tmp);
        Ok(out)
    }
}

#[cfg(windows)]
pub use windows_impl::*;

// On non-Windows targets (e.g. doing local Cargo checks on the Mac dev box),
// stub out the API so the rest of the crate still compiles.
#[cfg(not(windows))]
pub fn read_claude_ai_cookies() -> Result<std::collections::HashMap<String, String>, String> {
    Err("unsupported_platform".into())
}
