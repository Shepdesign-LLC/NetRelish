//! Frontend access to the extraction deny list (see `crate::denylist`).
//! The file path is fixed inside the app's config dir — neither command
//! accepts a path, so there is no containment to get wrong.

use crate::denylist;
use crate::error::Result;
use tauri::{AppHandle, Runtime};

#[tauri::command]
pub async fn denylist_get<R: Runtime>(app: AppHandle<R>) -> Result<String> {
    denylist::read(&app)
}

#[tauri::command]
pub async fn denylist_set<R: Runtime>(app: AppHandle<R>, contents: String) -> Result<()> {
    denylist::write(&app, &contents)
}
