//! Writing generated files to the user's real project directory.
//!
//! This is the feature the web tools cannot have, so it gets the most care.
//! Three rules, enforced here rather than trusted to the caller:
//!   1. Containment — nothing is written outside the chosen project root.
//!   2. Backup — an existing file is copied into .nr-backup/ before it changes.
//!   3. Atomicity — write to a temp file in the same directory, then rename.
//!      A crash mid-write leaves the original intact.

use crate::error::{Error, Result};
use serde::{Deserialize, Serialize};
use std::path::{Component, Path, PathBuf};

/// One generated file, as emitted by Zest, Mise or Scale.
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ExportFile {
    /// Project-relative path, e.g. "theme/assets/css/_tokens.css".
    pub path: String,
    pub contents: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WriteReport {
    pub written: Vec<String>,
    pub backed_up: Vec<String>,
}

/// Reject absolute paths, `..`, and anything else that would climb out.
fn resolve_inside(root: &Path, relative: &str) -> Result<PathBuf> {
    let candidate = Path::new(relative);

    let escapes = candidate.components().any(|c| {
        matches!(
            c,
            Component::ParentDir | Component::RootDir | Component::Prefix(_)
        )
    });
    if escapes || relative.trim().is_empty() {
        return Err(Error::OutsideProject(relative.to_string()));
    }

    let joined = root.join(candidate);

    // Canonicalize the deepest existing ancestor and confirm it is still under
    // root. This catches symlinks pointing outside the project.
    let mut probe = joined.as_path();
    let anchor = loop {
        if probe.exists() {
            break probe.canonicalize()?;
        }
        match probe.parent() {
            Some(parent) => probe = parent,
            None => return Err(Error::OutsideProject(relative.to_string())),
        }
    };

    let real_root = root.canonicalize()?;
    if !anchor.starts_with(&real_root) {
        return Err(Error::OutsideProject(relative.to_string()));
    }

    Ok(joined)
}

fn write_atomic(target: &Path, contents: &str) -> Result<()> {
    let dir = target.parent().ok_or_else(|| {
        Error::OutsideProject(target.to_string_lossy().to_string())
    })?;
    std::fs::create_dir_all(dir)?;

    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or_default();
    let temp = dir.join(format!(".nr-tmp-{stamp}"));

    std::fs::write(&temp, contents)?;
    std::fs::rename(&temp, target)?;
    Ok(())
}

/// Copy the current version into .nr-backup/<timestamp>/ before overwriting.
fn back_up(root: &Path, target: &Path, relative: &str, stamp: u64) -> Result<bool> {
    if !target.exists() {
        return Ok(false);
    }
    let dest = root.join(".nr-backup").join(stamp.to_string()).join(relative);
    if let Some(parent) = dest.parent() {
        std::fs::create_dir_all(parent)?;
    }
    std::fs::copy(target, dest)?;
    Ok(true)
}

/// Write a batch of generated files into the project.
///
/// The frontend must have shown the user a diff and received confirmation
/// before calling this. The command does not prompt.
#[tauri::command]
pub async fn write_project_files(
    project_root: String,
    files: Vec<ExportFile>,
) -> Result<WriteReport> {
    let root = PathBuf::from(&project_root);
    if !root.is_dir() {
        return Err(Error::NoProject);
    }

    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or_default();

    let mut report = WriteReport {
        written: Vec::new(),
        backed_up: Vec::new(),
    };

    // Resolve every path before writing any of them, so a bad entry in the
    // batch fails the whole thing instead of leaving a half-applied export.
    let resolved: Vec<(PathBuf, &ExportFile)> = files
        .iter()
        .map(|f| resolve_inside(&root, &f.path).map(|p| (p, f)))
        .collect::<Result<_>>()?;

    for (target, file) in resolved {
        if back_up(&root, &target, &file.path, stamp)? {
            report.backed_up.push(file.path.clone());
        }
        write_atomic(&target, &file.contents)?;
        report.written.push(file.path.clone());
    }

    Ok(report)
}

/// Read a file back so the UI can render a real diff before writing.
#[tauri::command]
pub async fn read_project_file(project_root: String, path: String) -> Result<Option<String>> {
    let root = PathBuf::from(&project_root);
    let target = resolve_inside(&root, &path)?;
    if !target.is_file() {
        return Ok(None);
    }
    Ok(Some(std::fs::read_to_string(target)?))
}
