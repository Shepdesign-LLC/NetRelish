//! Rust-side access to the one database.
//!
//! The pool is owned by tauri-plugin-sql (preloaded and migrated at startup,
//! see `tauri.conf.json > plugins > sql > preload`). The frontend reaches it
//! through the plugin's JS API via `src/lib/db.ts`; Rust borrows the same
//! pool here. One database, one schema, two doors.

use sqlx::{Pool, Sqlite};
use tauri::{AppHandle, Manager, Runtime};
use tauri_plugin_sql::{DbInstances, DbPool};

/// The connection string. Also the key `src/lib/db.ts` attaches with —
/// the two must match or the frontend opens a second pool.
pub const DB_URL: &str = "sqlite:netrelish.db";

/// Clone a handle to the shared sqlite pool, if the plugin has loaded it.
pub async fn sqlite_pool<R: Runtime>(app: &AppHandle<R>) -> Option<Pool<Sqlite>> {
    let instances = app.try_state::<DbInstances>()?;
    let lock = instances.0.read().await;
    match lock.get(DB_URL) {
        Some(DbPool::Sqlite(pool)) => Some(pool.clone()),
        _ => None,
    }
}

/// The jar new pages extract into (None = Brine). Set from the frontend via
/// `set_active_jar`; read by extraction at write time.
#[derive(Default)]
pub struct ActiveJar(pub std::sync::Mutex<Option<String>>);

/// Epoch milliseconds, the timestamp unit used across `items`.
pub fn now_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}
