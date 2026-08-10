//! The page-rendering pane.
//!
//! This is a real child WKWebView parented to the main window, not an iframe.
//! Iframes are a dead end for a browser: most of the web sets X-Frame-Options
//! or frame-ancestors and simply refuses to load. `Window::add_child` requires
//! tauri's `unstable` feature, which is why it is enabled in Cargo.toml.

use crate::error::{Error, Result};
use serde::{Deserialize, Serialize};
use tauri::{
    webview::{PageLoadEvent, WebviewBuilder},
    Emitter, LogicalPosition, LogicalSize, Manager, WebviewUrl, Window,
};

pub const PREVIEW_LABEL: &str = "preview";

/// Where the pane sits inside the main window, in logical (CSS) pixels.
/// The React layout owns these numbers and reports them down.
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Rect {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

fn parse_web_url(raw: &str) -> Result<url::Url> {
    let parsed = url::Url::parse(raw).map_err(|_| Error::BadUrl(raw.to_string()))?;
    // Only ever hand http(s) to the child webview. file:// or custom schemes
    // here would be a sandbox escape waiting to happen.
    match parsed.scheme() {
        "http" | "https" => Ok(parsed),
        _ => Err(Error::BadUrl(raw.to_string())),
    }
}

/// Open the pane, or navigate it if it already exists.
#[tauri::command]
pub async fn preview_open(window: Window, url: String, rect: Rect) -> Result<()> {
    let target = parse_web_url(&url)?;

    if let Some(existing) = window.get_webview(PREVIEW_LABEL) {
        existing.navigate(target)?;
        // The pane may be hidden behind the Brine surface; navigating to a
        // page always brings it back.
        existing.show()?;
        return Ok(());
    }

    let builder = WebviewBuilder::new(PREVIEW_LABEL, WebviewUrl::External(target))
        .incognito(false)
        .transparent(false)
        // Every finished main-frame load feeds Brine. The page itself gets
        // no bridge into the app — extraction pulls, nothing pushes.
        .on_page_load(|webview, payload| {
            if payload.event() == PageLoadEvent::Finished {
                // Keep the omnibox honest: link clicks and redirects inside
                // the pane never pass through the React side otherwise.
                let _ = webview.emit_to("main", "preview:navigated", payload.url().as_str());
                crate::extract::on_page_finished(webview, payload.url().clone());
            }
        });

    window.add_child(
        builder,
        LogicalPosition::new(rect.x, rect.y),
        LogicalSize::new(rect.width, rect.height),
    )?;

    Ok(())
}

/// Keep the native pane glued to the hole the React layout leaves for it.
/// Called on window resize and on sidebar collapse.
#[tauri::command]
pub async fn preview_set_bounds(window: Window, rect: Rect) -> Result<()> {
    let Some(webview) = window.get_webview(PREVIEW_LABEL) else {
        return Ok(());
    };
    webview.set_position(LogicalPosition::new(rect.x, rect.y))?;
    webview.set_size(LogicalSize::new(rect.width, rect.height))?;
    Ok(())
}

#[tauri::command]
pub async fn preview_close(window: Window) -> Result<()> {
    if let Some(webview) = window.get_webview(PREVIEW_LABEL) {
        webview.close()?;
    }
    Ok(())
}

/// Read the page's scroll position, for preserving a tab's exact state
/// before switching away from it or sealing it.
#[tauri::command]
pub async fn preview_get_scroll(window: Window) -> Result<f64> {
    let Some(webview) = window.get_webview(PREVIEW_LABEL) else {
        return Ok(0.0);
    };
    let (tx, rx) = tokio::sync::oneshot::channel::<f64>();
    let tx = std::sync::Mutex::new(Some(tx));
    webview.eval_with_callback("window.scrollY", move |json| {
        if let Some(tx) = tx.lock().unwrap_or_else(|p| p.into_inner()).take() {
            let _ = tx.send(json.parse::<f64>().unwrap_or(0.0));
        }
    })?;
    // If the page never answers (mid-navigation), a tab with scroll 0 is
    // still a preserved tab.
    Ok(tokio::time::timeout(std::time::Duration::from_millis(400), rx)
        .await
        .ok()
        .and_then(|r| r.ok())
        .unwrap_or(0.0))
}

/// Put a reopened page back where the reader left it.
#[tauri::command]
pub async fn preview_set_scroll(window: Window, y: f64) -> Result<()> {
    if let Some(webview) = window.get_webview(PREVIEW_LABEL) {
        webview.eval(format!("window.scrollTo(0, {y});"))?;
    }
    Ok(())
}

/// Hide the native pane without destroying it, so chrome surfaces (Brine)
/// can render in the stage. The page, its session and its scroll position
/// all survive — hiding is not closing.
#[tauri::command]
pub async fn preview_hide(window: Window) -> Result<()> {
    if let Some(webview) = window.get_webview(PREVIEW_LABEL) {
        webview.hide()?;
    }
    Ok(())
}

#[tauri::command]
pub async fn preview_show(window: Window) -> Result<()> {
    if let Some(webview) = window.get_webview(PREVIEW_LABEL) {
        webview.show()?;
    }
    Ok(())
}
