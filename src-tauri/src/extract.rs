//! Everything you browse is preserved into Brine.
//!
//! On every finished main-frame load in the preview webview (wired in
//! `commands::preview`), evaluate Readability inside the page and pull the
//! result back over the platform's completion handler — the page is never
//! handed an IPC bridge, a custom protocol, or any other way in. Data flows
//! one direction: Rust asks, the page answers, Rust writes.
//!
//! The row key is the navigation URL reported by the webview itself, not
//! whatever the page's scripts claim — a hostile page can only ever pollute
//! its own row.

use crate::{db, denylist};
use serde::Deserialize;
use tauri::{webview::Webview, AppHandle, Emitter, Manager, Runtime, Url};

/// Emitted to the main window after each upsert so the Brine surface and
/// rail count refresh live.
pub const BRINE_CHANGED: &str = "brine:changed";

#[derive(Debug, Deserialize)]
struct Extraction {
    ok: bool,
    title: Option<String>,
    byline: Option<String>,
    excerpt: Option<String>,
    site: Option<String>,
    text: Option<String>,
    ms: Option<f64>,
    error: Option<String>,
}

/// The content script: extract.js with the vendored Readability source
/// spliced over its marker. Assembled once, ~95KB.
fn script() -> &'static str {
    static SCRIPT: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    SCRIPT.get_or_init(|| {
        include_str!("../inject/extract.js").replace(
            "/*__NR_READABILITY__*/",
            include_str!("../inject/readability.js"),
        )
    })
}

/// Entry point, called on `PageLoadEvent::Finished`. Files into the active
/// jar (or Brine) and respects the deny list.
pub fn on_page_finished<R: Runtime>(webview: Webview<R>, url: Url) {
    schedule(webview, url, None);
}

/// `⌘J` — explicit user intent. Bypasses the deny list and moves the row
/// into `jar_id` even if Brine already holds it.
pub fn jar_page_now<R: Runtime>(webview: Webview<R>, url: Url, jar_id: String) {
    schedule(webview, url, Some(jar_id));
}

fn schedule<R: Runtime>(webview: Webview<R>, url: Url, jar_override: Option<String>) {
    if !matches!(url.scheme(), "http" | "https") {
        return;
    }

    let app = webview.app_handle().clone();
    tauri::async_runtime::spawn(async move {
        if jar_override.is_none()
            && denylist::is_denied(url.as_str(), &denylist::patterns(&app))
        {
            return;
        }

        let result = webview.eval_with_callback(script(), move |json| {
            let app = app.clone();
            let url = url.clone();
            let jar_override = jar_override.clone();
            tauri::async_runtime::spawn(async move {
                record(&app, &url, &json, jar_override.as_deref()).await;
            });
        });

        if let Err(e) = result {
            eprintln!("extract: eval failed: {e}");
        }
    });
}

async fn record<R: Runtime>(
    app: &AppHandle<R>,
    url: &Url,
    json: &str,
    jar_override: Option<&str>,
) {
    // Empty string means the eval produced nothing (navigated away mid-run,
    // or the page refused to evaluate). Nothing to preserve.
    let Ok(extraction) = serde_json::from_str::<Extraction>(json) else {
        if !json.is_empty() {
            eprintln!("extract: unparseable result from {url}");
        }
        return;
    };

    if !extraction.ok {
        eprintln!(
            "extract: script error on {url}: {}",
            extraction.error.as_deref().unwrap_or("unknown")
        );
        // Fall through — even a failed parse still has a URL and title worth
        // keeping. Closing must stay free.
    }

    let title = extraction
        .title
        .filter(|t| !t.trim().is_empty())
        .unwrap_or_else(|| url.host_str().unwrap_or("Untitled").to_string());
    let body = extraction.text.unwrap_or_default();
    let meta = serde_json::json!({
        "byline": extraction.byline,
        "excerpt": extraction.excerpt,
        "site": extraction.site,
        "extract_ms": extraction.ms,
    })
    .to_string();

    #[cfg(debug_assertions)]
    if let Some(ms) = extraction.ms {
        eprintln!("extract: {url} in {ms:.1}ms, {} chars", body.len());
    }

    let Some(pool) = db::sqlite_pool(app).await else {
        eprintln!("extract: database not loaded, dropping {url}");
        return;
    };

    // New rows land in the explicit target (⌘J) or the active jar; NULL is
    // Brine. On revisit, content and touched_at refresh but the row only
    // MOVES between jars for an explicit ⌘J — never from mere browsing.
    // Filing silently is how trust in the jar dies.
    let jar_id: Option<String> = jar_override.map(String::from).or_else(|| {
        app.try_state::<db::ActiveJar>()
            .and_then(|s| s.0.lock().unwrap_or_else(|p| p.into_inner()).clone())
    });

    let sql = if jar_override.is_some() {
        "INSERT INTO items (id, jar_id, kind, url, title, body, meta, created_at, touched_at)
         VALUES (?1, ?2, 'page', ?3, ?4, ?5, ?6, ?7, ?7)
         ON CONFLICT(url) WHERE url IS NOT NULL DO UPDATE SET
           jar_id = excluded.jar_id,
           title = excluded.title,
           body = excluded.body,
           meta = excluded.meta,
           touched_at = excluded.touched_at"
    } else {
        "INSERT INTO items (id, jar_id, kind, url, title, body, meta, created_at, touched_at)
         VALUES (?1, ?2, 'page', ?3, ?4, ?5, ?6, ?7, ?7)
         ON CONFLICT(url) WHERE url IS NOT NULL DO UPDATE SET
           title = excluded.title,
           body = excluded.body,
           meta = excluded.meta,
           touched_at = excluded.touched_at"
    };

    let upsert = sqlx::query(sql)
        .bind(uuid::Uuid::new_v4().to_string())
        .bind(&jar_id)
        .bind(url.as_str())
        .bind(&title)
        .bind(&body)
        .bind(&meta)
        .bind(db::now_ms())
        .execute(&pool)
        .await;

    match upsert {
        Ok(_) => {
            let _ = app.emit_to("main", BRINE_CHANGED, ());
        }
        Err(e) => eprintln!("extract: write failed for {url}: {e}"),
    }
}
