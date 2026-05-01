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
            let _ = windows::Win32::Foundation::LocalFree(
                windows::Win32::Foundation::HLOCAL(output.pbData as *mut _),
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

        // Two-stage read:
        //   1. Try a plain shared open. Works if Chromium opened the file
        //      with FILE_SHARE_READ (older builds, some configurations).
        //   2. If we get a sharing violation, ask the Windows Restart Manager
        //      to find and forcibly stop the Chromium child process that's
        //      holding the lock, then race to read the file before Chromium
        //      restarts the child. No admin required — RM is per-user.
        let bytes = read_bytes_shared(&src)
            .or_else(|_| read_bytes_via_restart_manager(&src))
            .map_err(|e| format!("cookies_read_src:{e}"))?;

        let tmp = std::env::temp_dir().join(format!(
            "claude-o-meter-cookies-{}.db",
            std::process::id()
        ));
        std::fs::write(&tmp, &bytes).map_err(|e| format!("cookies_write_tmp:{e}"))?;

        let conn = rusqlite::Connection::open(&tmp)
            .map_err(|e| format!("cookies_open:{e}"))?;
        let mut stmt = conn
            .prepare("SELECT host_key, name, encrypted_value FROM cookies WHERE host_key LIKE '%claude%' OR host_key LIKE '%anthropic%'")
            .map_err(|e| format!("cookies_prepare:{e}"))?;
        let mut rows = stmt
            .query([])
            .map_err(|e| format!("cookies_query:{e}"))?;

        let mut out = std::collections::HashMap::new();
        let mut prefixes_seen: std::collections::HashMap<String, u32> = std::collections::HashMap::new();
        let mut total_rows = 0;
        let mut decrypt_failures = 0;
        while let Ok(Some(row)) = rows.next() {
            total_rows += 1;
            let _host: String = row.get(0).unwrap_or_default();
            let name: String = match row.get(1) { Ok(v) => v, _ => continue };
            let blob: Vec<u8> = match row.get(2) { Ok(v) => v, _ => continue };

            // Record the 3-byte prefix so we can identify the encryption format.
            let prefix = String::from_utf8_lossy(
                &blob.iter().take(3).copied().collect::<Vec<u8>>()
            ).to_string();
            *prefixes_seen.entry(prefix).or_insert(0) += 1;

            if let Some(v) = decrypt_cookie(&blob, &key) {
                out.insert(name, v);
            } else {
                decrypt_failures += 1;
            }
        }
        let _ = std::fs::remove_file(&tmp);

        if out.is_empty() {
            return Err(format!(
                "DEBUG rows={} decrypt_failed={} prefixes={:?}",
                total_rows, decrypt_failures, prefixes_seen
            ));
        }

        Ok(out)
    }

    fn read_bytes_shared(src: &std::path::Path) -> Result<Vec<u8>, String> {
        use std::io::Read;
        use std::os::windows::fs::OpenOptionsExt;
        let mut bytes = Vec::new();
        std::fs::OpenOptions::new()
            .read(true)
            .share_mode(7) // FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE
            .open(src)
            .map_err(|e| format!("open:{e}"))?
            .read_to_end(&mut bytes)
            .map_err(|e| format!("read:{e}"))?;
        Ok(bytes)
    }

    /// Use the Windows Restart Manager to find and forcibly stop the
    /// process(es) holding the file open, then race to read the bytes
    /// before that process gets respawned by its parent. No admin needed —
    /// RM operates within the user session.
    fn read_bytes_via_restart_manager(src: &std::path::Path) -> Result<Vec<u8>, String> {
        use windows::core::PCWSTR;
        use windows::Win32::System::RestartManager::{
            RmEndSession, RmForceShutdown, RmGetList, RmRegisterResources, RmShutdown,
            RmStartSession, CCH_RM_SESSION_KEY, RM_PROCESS_INFO,
        };

        // RmStartSession needs a buffer of CCH_RM_SESSION_KEY+1 wide chars
        // for the session-key string.
        let mut session_key = vec![0u16; (CCH_RM_SESSION_KEY as usize) + 1];
        let mut session_handle: u32 = 0;
        let rc = unsafe {
            RmStartSession(
                &mut session_handle,
                0,
                windows::core::PWSTR(session_key.as_mut_ptr()),
            )
        };
        if rc.0 != 0 { return Err(format!("rm_start:{}", rc.0)); }

        // Wide path with NUL terminator.
        let path_w: Vec<u16> = src
            .as_os_str()
            .to_string_lossy()
            .encode_utf16()
            .chain(std::iter::once(0))
            .collect();
        let path_ptr = PCWSTR(path_w.as_ptr());
        let path_arr = [path_ptr];

        let rc = unsafe {
            RmRegisterResources(
                session_handle,
                Some(&path_arr),
                None, // applications
                None, // services
            )
        };
        if rc.0 != 0 {
            unsafe { let _ = RmEndSession(session_handle); }
            return Err(format!("rm_register:{}", rc.0));
        }

        // Discover (we don't actually use the list — just need RM to know
        // about the lock holders before RmShutdown).
        let mut needed: u32 = 0;
        let mut count: u32 = 0;
        let mut reasons: u32 = 0;
        let _ = unsafe {
            RmGetList(
                session_handle,
                &mut needed,
                &mut count,
                None,
                &mut reasons,
            )
        };
        if needed > 0 {
            count = needed;
            let mut info: Vec<RM_PROCESS_INFO> = vec![RM_PROCESS_INFO::default(); needed as usize];
            let _ = unsafe {
                RmGetList(
                    session_handle,
                    &mut needed,
                    &mut count,
                    Some(info.as_mut_ptr()),
                    &mut reasons,
                )
            };
        }

        // Force-shutdown the holders. RmForceShutdown == 1.
        let _ = unsafe {
            RmShutdown(session_handle, RmForceShutdown.0 as u32, None)
        };

        // Race window: read as fast as possible before Chromium relaunches
        // its network service. A few retries with tiny sleeps wins reliably.
        let mut last_err = String::from("no_attempt");
        for attempt in 0..6 {
            match read_bytes_shared(src) {
                Ok(b) => {
                    unsafe { let _ = RmEndSession(session_handle); }
                    return Ok(b);
                }
                Err(e) => {
                    last_err = e;
                    std::thread::sleep(std::time::Duration::from_millis(40 * (attempt + 1)));
                }
            }
        }

        unsafe { let _ = RmEndSession(session_handle); }
        Err(format!("rm_read_lost_race:{last_err}"))
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
