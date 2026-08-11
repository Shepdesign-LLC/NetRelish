//! Saved logins, vaulted in the macOS Keychain.
//!
//! The rules (docs/ROADMAP.md):
//! - Passwords live in the Keychain, never in netrelish.db — nothing the
//!   search, extraction or engine code paths touch can ever see one.
//! - The fill path runs Rust → page. The chrome webview (React) only ever
//!   receives hosts and usernames; password bytes exist in this module and
//!   in the page's own form fields, nowhere else.
//! - Saving and filling are user gestures. Nothing here runs on its own.
//!
//! Items are generic-password entries: service "NetRelish: {host}",
//! account = username, label "NetRelish" (the label is the enumeration
//! key for the management list).

use crate::commands::preview::PREVIEW_LABEL;
use crate::error::{Error, Result};
use security_framework::item::{ItemClass, ItemSearchOptions, Limit, SearchResult};
use security_framework::passwords::{
    delete_generic_password, get_generic_password, set_generic_password_options,
};
use security_framework::passwords_options::PasswordOptions;
use serde::Serialize;
use tauri::{Manager, Window};

const SERVICE_PREFIX: &str = "NetRelish: ";
const LABEL: &str = "NetRelish";

#[derive(Debug, Clone, Serialize)]
pub struct SavedLogin {
    pub host: String,
    pub username: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct LoginProbe {
    pub host: String,
    pub has_login: bool,
    pub usernames: Vec<String>,
}

fn service_for(host: &str) -> String {
    format!("{SERVICE_PREFIX}{host}")
}

/// The host of the page actually loaded in the native pane — read from the
/// webview itself, never trusted from chrome state. Credentials only ever
/// move over https (http is allowed for localhost development).
fn preview_host(window: &Window) -> Result<(tauri::Webview, String)> {
    let webview = window.get_webview(PREVIEW_LABEL).ok_or(Error::NoPage)?;
    let url = webview.url()?;
    let host = url.host_str().ok_or(Error::NoPage)?.to_string();
    let local = host == "localhost" || host == "127.0.0.1";
    if url.scheme() != "https" && !(url.scheme() == "http" && local) {
        return Err(Error::Keychain(format!(
            "logins only work on secure (https) pages — this page is {}",
            url.scheme()
        )));
    }
    Ok((webview, host))
}

/// Evaluate a JS expression in the page and wait for its JSON result.
async fn eval_json(webview: &tauri::Webview, js: &str) -> Result<serde_json::Value> {
    let (tx, rx) = tokio::sync::oneshot::channel::<String>();
    let tx = std::sync::Mutex::new(Some(tx));
    webview.eval_with_callback(js, move |json| {
        if let Some(tx) = tx.lock().unwrap_or_else(|p| p.into_inner()).take() {
            let _ = tx.send(json);
        }
    })?;
    let raw = tokio::time::timeout(std::time::Duration::from_millis(600), rx)
        .await
        .map_err(|_| Error::Keychain("the page did not answer".into()))?
        .map_err(|_| Error::Keychain("the page did not answer".into()))?;
    serde_json::from_str(&raw).map_err(|e| Error::Keychain(format!("bad page answer: {e}")))
}

/// Usernames saved for one host, for the key affordance and the fill picker.
fn usernames_for(host: &str) -> Vec<String> {
    let results = ItemSearchOptions::new()
        .class(ItemClass::generic_password())
        .service(&service_for(host))
        .load_attributes(true)
        .limit(Limit::All)
        .search()
        .unwrap_or_default();
    let mut names: Vec<String> = results
        .iter()
        .filter_map(SearchResult::simplify_dict)
        .filter_map(|d| d.get("acct").cloned())
        .collect();
    names.sort();
    names.dedup();
    names
}

/// Does the current page show a login form, and do we hold logins for it?
/// Runs on every navigation — detection is a suggestion, per the spec.
#[tauri::command]
pub async fn credential_probe(window: Window) -> Result<LoginProbe> {
    let Ok((webview, host)) = preview_host(&window) else {
        // Not an https page (or no page): no affordance, no error noise.
        return Ok(LoginProbe { host: String::new(), has_login: false, usernames: vec![] });
    };
    let has_login = eval_json(
        &webview,
        "(() => { const p = document.querySelector('input[type=\"password\"]'); \
         return !!p; })()",
    )
    .await
    .ok()
    .and_then(|v| v.as_bool())
    .unwrap_or(false);
    let usernames = usernames_for(&host);
    Ok(LoginProbe { host, has_login, usernames })
}

/// Pull the login the user typed into the current page and vault it.
/// The password travels page → here → Keychain and is dropped.
#[tauri::command]
pub async fn credential_save_from_page(window: Window) -> Result<SavedLogin> {
    let (webview, host) = preview_host(&window)?;
    let captured = eval_json(
        &webview,
        r#"(() => {
  const pw = Array.from(document.querySelectorAll('input[type="password"]')).find(i => i.value);
  if (!pw) return "";
  const scope = pw.form || document;
  const fields = Array.from(scope.querySelectorAll('input[type="email"], input[type="text"], input[autocomplete~="username"]'))
    .filter(i => i.value && i !== pw);
  const named = fields.find(i => (i.getAttribute("autocomplete") || "").includes("username"));
  const u = (named || fields[fields.length - 1] || {}).value || "";
  return JSON.stringify({ u, p: pw.value });
})()"#,
    )
    .await?;
    // The expression returns a JSON string ("" when nothing is typed), which
    // arrives double-encoded.
    let inner = captured.as_str().unwrap_or("");
    if inner.is_empty() {
        return Err(Error::Keychain(
            "nothing to save — type your login into the page first, then save".into(),
        ));
    }
    let parsed: serde_json::Value = serde_json::from_str(inner)
        .map_err(|e| Error::Keychain(format!("bad page answer: {e}")))?;
    let username = parsed["u"].as_str().unwrap_or("").trim().to_string();
    let password = parsed["p"].as_str().unwrap_or("");
    if password.is_empty() {
        return Err(Error::Keychain(
            "nothing to save — type your login into the page first, then save".into(),
        ));
    }
    if username.is_empty() {
        return Err(Error::Keychain(
            "couldn't find the username field — fill it in, then save".into(),
        ));
    }

    let mut options = PasswordOptions::new_generic_password(&service_for(&host), &username);
    options.set_label(LABEL);
    options.set_description("NetRelish login");
    set_generic_password_options(password.as_bytes(), options)?;

    Ok(SavedLogin { host, username })
}

/// Fill the current page's login form from the Keychain. The password goes
/// straight into the page; the caller only learns which username was used.
#[tauri::command]
pub async fn credential_fill(window: Window, username: Option<String>) -> Result<String> {
    let (webview, host) = preview_host(&window)?;
    let username = match username {
        Some(u) => u,
        None => usernames_for(&host)
            .into_iter()
            .next()
            .ok_or_else(|| Error::Keychain(format!("no login saved for {host}")))?,
    };
    let password = get_generic_password(&service_for(&host), &username)
        .map_err(|_| Error::Keychain(format!("no login saved for {host}")))?;
    let password = String::from_utf8(password)
        .map_err(|_| Error::Keychain("stored password is not text".into()))?;

    // serde_json::to_string produces valid JS string literals — the only
    // way credential text ever enters an eval.
    let u_js = serde_json::to_string(&username).map_err(|e| Error::Keychain(e.to_string()))?;
    let p_js = serde_json::to_string(&password).map_err(|e| Error::Keychain(e.to_string()))?;
    let js = format!(
        r#"(() => {{
  const setVal = (el, v) => {{
    Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set.call(el, v);
    el.dispatchEvent(new Event("input", {{ bubbles: true }}));
    el.dispatchEvent(new Event("change", {{ bubbles: true }}));
  }};
  const pw = document.querySelector('input[type="password"]');
  if (!pw) return false;
  const scope = pw.form || document;
  const fields = Array.from(scope.querySelectorAll('input[type="email"], input[type="text"], input[autocomplete~="username"]'))
    .filter(i => i !== pw);
  const named = fields.find(i => (i.getAttribute("autocomplete") || "").includes("username"));
  const u = named || fields[fields.length - 1];
  if (u) setVal(u, {u_js});
  setVal(pw, {p_js});
  return true;
}})()"#
    );
    let filled = eval_json(&webview, &js).await?;
    if filled.as_bool() != Some(true) {
        return Err(Error::Keychain("no login form on this page".into()));
    }
    Ok(username)
}

/// Every saved login, for the management list. Usernames and hosts only.
#[tauri::command]
pub async fn credential_list() -> Result<Vec<SavedLogin>> {
    let results = ItemSearchOptions::new()
        .class(ItemClass::generic_password())
        .label(LABEL)
        .load_attributes(true)
        .limit(Limit::All)
        .search()
        .unwrap_or_default();
    let mut logins: Vec<SavedLogin> = results
        .iter()
        .filter_map(SearchResult::simplify_dict)
        .filter_map(|d| {
            let host = d.get("svce")?.strip_prefix(SERVICE_PREFIX)?.to_string();
            let username = d.get("acct")?.clone();
            Some(SavedLogin { host, username })
        })
        .collect();
    logins.sort_by(|a, b| (&a.host, &a.username).cmp(&(&b.host, &b.username)));
    logins.dedup_by(|a, b| a.host == b.host && a.username == b.username);
    Ok(logins)
}

#[tauri::command]
pub async fn credential_delete(host: String, username: String) -> Result<()> {
    delete_generic_password(&service_for(&host), &username)?;
    Ok(())
}
