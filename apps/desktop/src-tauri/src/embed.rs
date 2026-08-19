//! The semantic layer: a local ONNX sentence-embedding model
//! (all-MiniLM-L6-v2, 384 dims), run with `ort` on Apple Silicon.
//!
//! Everything happens off the UI thread: single items embed on a blocking
//! task right after extraction; the backfill walks un-embedded items in
//! batches. Vectors land in the `embeddings` table (schema §6) as little-
//! endian f32 blobs. Nothing here ever leaves the machine.

use crate::db;
use ort::session::Session;
use ort::value::Tensor;
use std::path::PathBuf;
use std::sync::{Mutex, OnceLock};
use tauri::{AppHandle, Emitter, Manager, Runtime};
use tokenizers::Tokenizer;

pub const DIM: usize = 384;
const MAX_TOKENS: usize = 256;

struct Engine {
    session: Mutex<Session>,
    tokenizer: Tokenizer,
}

static ENGINE: OnceLock<Result<Engine, String>> = OnceLock::new();

fn model_dir<R: Runtime>(app: &AppHandle<R>) -> Option<PathBuf> {
    // Bundled builds carry the model as a resource; dev runs read it
    // straight out of src-tauri/models.
    if let Ok(dir) = app.path().resource_dir() {
        let bundled = dir.join("models");
        if bundled.join("all-MiniLM-L6-v2.onnx").exists() {
            return Some(bundled);
        }
    }
    #[cfg(debug_assertions)]
    {
        let dev = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("models");
        if dev.join("all-MiniLM-L6-v2.onnx").exists() {
            return Some(dev);
        }
    }
    None
}

fn engine<R: Runtime>(app: &AppHandle<R>) -> Result<&'static Engine, String> {
    let dir = model_dir(app);
    ENGINE
        .get_or_init(|| {
            let dir = dir.ok_or("embedding model not found in resources")?;
            let session = Session::builder()
                .and_then(|mut b| b.commit_from_file(dir.join("all-MiniLM-L6-v2.onnx")))
                .map_err(|e| format!("onnx session: {e}"))?;
            let tokenizer = Tokenizer::from_file(dir.join("tokenizer.json"))
                .map_err(|e| format!("tokenizer: {e}"))?;
            Ok(Engine {
                session: Mutex::new(session),
                tokenizer,
            })
        })
        .as_ref()
        .map_err(|e| e.clone())
}

/// Embed one text: tokenize, run the model, mean-pool over the attention
/// mask, L2-normalize. Pure CPU work — call from a blocking task.
fn embed_blocking(engine: &Engine, text: &str) -> Result<Vec<f32>, String> {
    #[cfg(debug_assertions)]
    let t0 = std::time::Instant::now();
    let result = embed_inner(engine, text);
    #[cfg(debug_assertions)]
    eprintln!("engine: embed {:.1}ms", t0.elapsed().as_secs_f64() * 1000.0);
    result
}

fn embed_inner(engine: &Engine, text: &str) -> Result<Vec<f32>, String> {
    let encoding = engine
        .tokenizer
        .encode(text, true)
        .map_err(|e| format!("encode: {e}"))?;

    let n = encoding.get_ids().len().min(MAX_TOKENS);
    let ids: Vec<i64> = encoding.get_ids()[..n].iter().map(|&i| i as i64).collect();
    let mask: Vec<i64> = encoding.get_attention_mask()[..n]
        .iter()
        .map(|&i| i as i64)
        .collect();
    let types: Vec<i64> = encoding.get_type_ids()[..n]
        .iter()
        .map(|&i| i as i64)
        .collect();

    let mut session = engine.session.lock().unwrap_or_else(|p| p.into_inner());
    let outputs = session
        .run(
            ort::inputs![
                "input_ids" => Tensor::from_array(([1usize, n], ids)).map_err(|e| e.to_string())?,
                "attention_mask" => Tensor::from_array(([1usize, n], mask.clone())).map_err(|e| e.to_string())?,
                "token_type_ids" => Tensor::from_array(([1usize, n], types)).map_err(|e| e.to_string())?,
            ],
        )
        .map_err(|e| format!("run: {e}"))?;

    let (_, data) = outputs[0]
        .try_extract_tensor::<f32>()
        .map_err(|e| format!("extract: {e}"))?;

    // Mean pool tokens where the attention mask is 1, then normalize.
    let mut pooled = vec![0f32; DIM];
    let mut count = 0f32;
    for (t, &m) in mask.iter().enumerate() {
        if m == 1 {
            count += 1.0;
            let row = &data[t * DIM..(t + 1) * DIM];
            for (p, &v) in pooled.iter_mut().zip(row) {
                *p += v;
            }
        }
    }
    if count > 0.0 {
        for p in pooled.iter_mut() {
            *p /= count;
        }
    }
    let norm = pooled.iter().map(|v| v * v).sum::<f32>().sqrt().max(1e-12);
    for p in pooled.iter_mut() {
        *p /= norm;
    }
    Ok(pooled)
}

pub fn to_blob(vector: &[f32]) -> Vec<u8> {
    vector.iter().flat_map(|v| v.to_le_bytes()).collect()
}

pub fn from_blob(blob: &[u8]) -> Vec<f32> {
    blob.chunks_exact(4)
        .map(|c| f32::from_le_bytes([c[0], c[1], c[2], c[3]]))
        .collect()
}

/// What the model actually reads for an item: title carries a lot of signal
/// on short pages, body carries it on long ones.
fn embeddable_text(title: &str, body: &str) -> String {
    let mut text = String::with_capacity(title.len() + 1 + 2000.min(body.len()));
    text.push_str(title);
    text.push('\n');
    text.push_str(&body.chars().take(2000).collect::<String>());
    text
}

/// Embed a query string (⌘K semantic search).
pub async fn embed_query<R: Runtime>(
    app: &AppHandle<R>,
    text: String,
) -> Result<Vec<f32>, String> {
    let app = app.clone();
    tauri::async_runtime::spawn_blocking(move || {
        let engine = engine(&app)?;
        embed_blocking(engine, &text)
    })
    .await
    .map_err(|e| e.to_string())?
}

/// Embed one item and store its vector. Fire-and-forget from extraction.
pub fn spawn_embed_item<R: Runtime>(app: AppHandle<R>, item_id: String, title: String, body: String) {
    tauri::async_runtime::spawn(async move {
        let text = embeddable_text(&title, &body);
        let vector = {
            let app = app.clone();
            tauri::async_runtime::spawn_blocking(move || {
                engine(&app).and_then(|e| embed_blocking(e, &text))
            })
            .await
        };
        let Ok(Ok(vector)) = vector else {
            return;
        };
        if let Some(pool) = db::sqlite_pool(&app).await {
            let _ = sqlx::query(
                "INSERT OR REPLACE INTO embeddings (item_id, vector) VALUES (?1, ?2)",
            )
            .bind(&item_id)
            .bind(to_blob(&vector))
            .execute(&pool)
            .await;
        }
    });
}

/// Walk every item that has text but no vector, oldest debt first. Runs at
/// startup; inherently resumable across quits because "done" is defined by
/// the join, not by a cursor.
pub fn spawn_backfill<R: Runtime>(app: AppHandle<R>) {
    tauri::async_runtime::spawn(async move {
        let mut total = 0usize;
        loop {
            let Some(pool) = db::sqlite_pool(&app).await else {
                return;
            };
            let batch: Vec<(String, String, String)> = match sqlx::query_as(
                "SELECT i.id, i.title, coalesce(i.body, '')
                 FROM items i
                 LEFT JOIN embeddings e ON e.item_id = i.id
                 WHERE e.item_id IS NULL AND i.body IS NOT NULL AND length(i.body) > 0
                 ORDER BY i.touched_at DESC
                 LIMIT 8",
            )
            .fetch_all(&pool)
            .await
            {
                Ok(rows) => rows,
                Err(_) => return,
            };
            if batch.is_empty() {
                if total > 0 {
                    eprintln!("engine: backfill complete, {total} items embedded");
                    let _ = app.emit_to("main", "engine:backfilled", total);
                }
                return;
            }
            for (id, title, body) in batch {
                let text = embeddable_text(&title, &body);
                let vector = {
                    let app = app.clone();
                    tauri::async_runtime::spawn_blocking(move || {
                        engine(&app).and_then(|e| embed_blocking(e, &text))
                    })
                    .await
                };
                match vector {
                    Ok(Ok(v)) => {
                        let _ = sqlx::query(
                            "INSERT OR REPLACE INTO embeddings (item_id, vector) VALUES (?1, ?2)",
                        )
                        .bind(&id)
                        .bind(to_blob(&v))
                        .execute(&pool)
                        .await;
                        total += 1;
                    }
                    Ok(Err(e)) => {
                        // Model unavailable: stop quietly, retry next launch.
                        eprintln!("engine: backfill halted: {e}");
                        return;
                    }
                    Err(_) => return,
                }
            }
            // Yield between batches; embedding is background work, always.
            tokio::time::sleep(std::time::Duration::from_millis(150)).await;
        }
    });
}
