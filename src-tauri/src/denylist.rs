//! The extraction deny list.
//!
//! One pattern per line in a plain text file the user can open in any editor;
//! `#` starts a comment. A page whose full URL contains a pattern
//! (case-insensitive) is never preserved into Brine. Read fresh on every
//! navigation so edits apply immediately — human page loads are far too
//! infrequent for the file read to matter.

use crate::error::{Error, Result};
use std::path::PathBuf;
use tauri::{AppHandle, Manager, Runtime};

const FILE_NAME: &str = "denylist.txt";

const DEFAULT: &str = "\
# NetRelish deny list — pages whose address contains a line below are
# never preserved into Brine. One pattern per line, # starts a comment.
# Matching is case-insensitive, anywhere in the address.

accounts.google.com
mail.google.com
outlook.live.com
/login
/signin
/sign-in
/checkout
/cart
";

/// The deny list always lives at a fixed name inside the app's own config
/// dir — no caller-supplied path ever reaches the filesystem.
pub fn path<R: Runtime>(app: &AppHandle<R>) -> Result<PathBuf> {
    let dir = app.path().app_config_dir().map_err(tauri::Error::from)?;
    Ok(dir.join(FILE_NAME))
}

/// Seed the default file on first run so there is always something to edit.
pub fn ensure_default<R: Runtime>(app: &AppHandle<R>) -> Result<()> {
    let path = path(app)?;
    if !path.exists() {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::write(&path, DEFAULT)?;
    }
    Ok(())
}

pub fn read<R: Runtime>(app: &AppHandle<R>) -> Result<String> {
    ensure_default(app)?;
    Ok(std::fs::read_to_string(path(app)?)?)
}

pub fn write<R: Runtime>(app: &AppHandle<R>, contents: &str) -> Result<()> {
    let path = path(app)?;
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    std::fs::write(&path, contents).map_err(Error::from)
}

/// Patterns from the file: trimmed, comments and blanks dropped, lowercased.
pub fn patterns<R: Runtime>(app: &AppHandle<R>) -> Vec<String> {
    read(app)
        .map(|text| {
            text.lines()
                .map(str::trim)
                .filter(|l| !l.is_empty() && !l.starts_with('#'))
                .map(str::to_lowercase)
                .collect()
        })
        .unwrap_or_default()
}

pub fn is_denied(url: &str, patterns: &[String]) -> bool {
    let url = url.to_lowercase();
    patterns.iter().any(|p| url.contains(p.as_str()))
}
