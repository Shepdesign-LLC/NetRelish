//! Active-jar state and the explicit "Jar it" gesture.
//!
//! Jar CRUD itself lives in the frontend's `src/lib/db.ts` — these commands
//! exist for the two things the frontend cannot do: telling extraction where
//! new pages belong, and force-filing the page currently in the native pane.

use crate::commands::preview::PREVIEW_LABEL;
use crate::db::ActiveJar;
use crate::error::{Error, Result};
use tauri::{AppHandle, Manager, Window};

/// The jar new pages extract into. None = Brine.
#[tauri::command]
pub async fn set_active_jar(app: AppHandle, jar_id: Option<String>) -> Result<()> {
    let state = app.state::<ActiveJar>();
    // A poisoned lock only means a writer panicked mid-store; the value
    // inside is still a plain Option and safe to replace.
    let mut guard = state.0.lock().unwrap_or_else(|p| p.into_inner());
    *guard = jar_id;
    Ok(())
}

/// `⌘J` — file the page in the preview pane into `jar_id`, right now.
/// Explicit user intent: bypasses the deny list, and moves the row into the
/// jar if Brine already holds it.
#[tauri::command]
pub async fn jar_page(window: Window, jar_id: String) -> Result<()> {
    let Some(webview) = window.get_webview(PREVIEW_LABEL) else {
        return Err(Error::NoPage);
    };
    let url = webview.url()?;
    if !matches!(url.scheme(), "http" | "https") {
        return Err(Error::NoPage);
    }
    crate::extract::jar_page_now(webview, url, jar_id);
    Ok(())
}
