//! The organization engine's frontend surface: suggestions for a jar, the
//! user's verdicts on them, and semantic search for ⌘K.

use crate::error::{Error, Result};
use crate::{db, embed, suggest};
use serde::Serialize;
use tauri::AppHandle;

#[tauri::command]
pub async fn suggest_for_jar(
    app: AppHandle,
    jar_id: String,
) -> Result<Vec<suggest::Suggestion>> {
    Ok(suggest::suggest_for_jar(&app, &jar_id).await)
}

/// Record accept/reject verdicts. Rejections weight future scoring; the
/// engine learns this user's boundaries.
#[tauri::command]
pub async fn suggestion_feedback(
    app: AppHandle,
    jar_id: String,
    item_ids: Vec<String>,
    action: String,
) -> Result<()> {
    if !matches!(action.as_str(), "accepted" | "rejected") {
        return Err(Error::BadUrl(action)); // closest existing shape; unreachable from our UI
    }
    let Some(pool) = db::sqlite_pool(&app).await else {
        return Ok(());
    };
    let now = db::now_ms();
    for id in item_ids {
        // INSERT OR REPLACE would delete the row and insert a fresh one, taking
        // its field_ts with it — every stamp reset to nothing, so every field
        // would lose the next merge. Upsert in place instead, and stamp only
        // the columns this write actually rewrites.
        let stamp = serde_json::json!({ "action": now, "at": now, "deleted_at": now }).to_string();
        let _ = sqlx::query(
            "INSERT INTO suggestion_feedback
               (item_id, jar_id, action, at, updated_at, field_ts)
             VALUES (?1, ?2, ?3, ?4, ?4, ?5)
             ON CONFLICT(item_id, jar_id) DO UPDATE SET
               action     = excluded.action,
               at         = excluded.at,
               updated_at = excluded.updated_at,
               deleted_at = NULL,
               field_ts   = json_patch(suggestion_feedback.field_ts, excluded.field_ts)",
        )
        .bind(&id)
        .bind(&jar_id)
        .bind(&action)
        .bind(now)
        .bind(&stamp)
        .execute(&pool)
        .await;
    }
    Ok(())
}

#[derive(Debug, Serialize)]
pub struct SemanticRow {
    pub id: String,
    pub url: Option<String>,
    pub title: String,
    pub jar_id: Option<String>,
    pub jar_name: Option<String>,
    pub snippet: String,
    pub distance: f64,
}

/// Nearest items by meaning, for ⌘K. The palette merges these BEHIND its
/// exact FTS matches — semantic recall never outranks a literal hit.
#[tauri::command]
pub async fn semantic_search(
    app: AppHandle,
    query: String,
    limit: i64,
) -> Result<Vec<SemanticRow>> {
    if query.trim().is_empty() {
        return Ok(vec![]);
    }
    let Some(pool) = db::sqlite_pool(&app).await else {
        return Ok(vec![]);
    };
    let vector = embed::embed_query(&app, query)
        .await
        .map_err(Error::Engine)?;
    let blob = embed::to_blob(&vector);

    // sqlite-vec's distance function over the schema's own embeddings
    // table — brute force is single-digit milliseconds at this scale.
    let rows = sqlx::query_as::<
        _,
        (String, Option<String>, String, Option<String>, Option<String>, String, f64),
    >(
        "SELECT i.id, i.url, i.title, i.jar_id, j.name,
                substr(coalesce(i.body, ''), 1, 200),
                vec_distance_cosine(e.vector, ?1) AS distance
         FROM embeddings e
         JOIN items i ON i.id = e.item_id
         LEFT JOIN jars j ON j.id = i.jar_id
         ORDER BY distance
         LIMIT ?2",
    )
    .bind(blob)
    .bind(limit.clamp(1, 50))
    .fetch_all(&pool)
    .await
    .map_err(|e| Error::Engine(e.to_string()))?;

    Ok(rows
        .into_iter()
        .map(|(id, url, title, jar_id, jar_name, snippet, distance)| SemanticRow {
            id,
            url,
            title,
            jar_id,
            jar_name,
            snippet,
            distance,
        })
        .collect())
}
