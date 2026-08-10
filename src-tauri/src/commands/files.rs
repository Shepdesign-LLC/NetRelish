//! Local files in jars (week 8). The paths handled here arrive exclusively
//! from the user's own drag-drop gesture — the drop IS the grant. Nothing
//! here accepts a path the user didn't hand us, and nothing writes.

use crate::error::Result;
use serde::Serialize;

const MAX_SEARCHABLE_BYTES: u64 = 200 * 1024;

/// Read a dropped text file's content for full-text search. Binary or
/// oversized files return None — the item still exists, just without body.
#[tauri::command]
pub async fn read_text_file(path: String) -> Result<Option<String>> {
    let meta = match std::fs::metadata(&path) {
        Ok(m) if m.is_file() && m.len() <= MAX_SEARCHABLE_BYTES => m,
        _ => return Ok(None),
    };
    let _ = meta;
    Ok(std::fs::read_to_string(&path).ok())
}

#[derive(Debug, Serialize)]
pub struct FileStat {
    pub id: String,
    pub exists: bool,
    pub mtime_ms: Option<i64>,
}

/// The path watcher: stat every watched file. Runs alongside the hourly
/// sweep — cheap, and enough to notice moved or edited files.
#[tauri::command]
pub async fn stat_files(entries: Vec<(String, String)>) -> Result<Vec<FileStat>> {
    Ok(entries
        .into_iter()
        .map(|(id, path)| {
            let meta = std::fs::metadata(&path).ok().filter(|m| m.is_file());
            FileStat {
                id,
                exists: meta.is_some(),
                mtime_ms: meta
                    .and_then(|m| m.modified().ok())
                    .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                    .map(|d| d.as_millis() as i64),
            }
        })
        .collect())
}
