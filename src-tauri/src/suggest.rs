//! The suggestion engine (§8): four on-device layers, blended into one
//! score per Brine item against one jar.
//!
//!   1. Sessions   — visited near a jar item in time, or reached from one
//!                   (referrer chain)
//!   2. Semantics  — cosine similarity to the jar's embedding centroid
//!   3. Entities   — shared domains, ticket IDs, repo paths
//!   4. Correction — the user's own accepts/rejects, weighted in
//!
//! Output is always a suggestion. Nothing here files anything.

use crate::{db, embed};
use serde::Serialize;
use std::collections::{HashMap, HashSet};
use tauri::{AppHandle, Runtime};

const SESSION_WINDOW_MS: i64 = 30 * 60 * 1000;
const THRESHOLD: f32 = 0.42;
const LIMIT: usize = 12;

// Signal weights. Semantics carries the score; the others nudge it.
const W_SEMANTIC: f32 = 0.62;
const W_DOMAIN: f32 = 0.10;
const W_ENTITY: f32 = 0.14;
const W_SESSION: f32 = 0.06;
const W_REFERRER: f32 = 0.08;
const W_REJECTED: f32 = 0.50;

#[derive(Debug, Serialize)]
pub struct Suggestion {
    pub item_id: String,
    pub title: String,
    pub url: Option<String>,
    pub score: f32,
}

struct Entities {
    domain: Option<String>,
    tickets: HashSet<String>,
    repos: HashSet<String>,
}

fn ticket_regex() -> &'static regex::Regex {
    static RE: std::sync::OnceLock<regex::Regex> = std::sync::OnceLock::new();
    RE.get_or_init(|| regex::Regex::new(r"\b[A-Z]{2,6}-\d+\b").expect("static regex"))
}

fn repo_regex() -> &'static regex::Regex {
    static RE: std::sync::OnceLock<regex::Regex> = std::sync::OnceLock::new();
    RE.get_or_init(|| {
        regex::Regex::new(r"(?:github|gitlab|bitbucket)\.(?:com|org)/([\w.-]+/[\w.-]+)")
            .expect("static regex")
    })
}

/// Domains, ticket IDs, repo paths — pulled from url + title + body head.
fn entities(url: Option<&str>, title: &str, body: &str) -> Entities {
    let domain = url
        .and_then(|u| url::Url::parse(u).ok())
        .and_then(|u| u.host_str().map(|h| h.trim_start_matches("www.").to_string()));
    let body_head: String = body.chars().take(4000).collect();
    let haystack = format!("{} {} {}", url.unwrap_or(""), title, body_head);
    let tickets = ticket_regex()
        .find_iter(&haystack)
        .map(|m| m.as_str().to_string())
        .collect();
    let repos = repo_regex()
        .captures_iter(&haystack)
        .map(|c| c[1].to_lowercase())
        .collect();
    Entities { domain, tickets, repos }
}

fn cosine(a: &[f32], b: &[f32]) -> f32 {
    // Vectors are stored normalized; the dot product is the cosine.
    a.iter().zip(b).map(|(x, y)| x * y).sum()
}

struct Row {
    id: String,
    url: Option<String>,
    title: String,
    body: String,
    touched_at: i64,
    referrer: Option<String>,
    vector: Option<Vec<f32>>,
}

async fn load_rows(
    pool: &sqlx::Pool<sqlx::Sqlite>,
    where_clause: &str,
    bind: Option<&str>,
) -> Vec<Row> {
    let sql = format!(
        "SELECT i.id, i.url, i.title, coalesce(i.body,''), i.touched_at,
                json_extract(i.meta, '$.referrer'), e.vector
         FROM items i LEFT JOIN embeddings e ON e.item_id = i.id
         WHERE {where_clause}
         ORDER BY i.touched_at DESC LIMIT 400"
    );
    let mut q = sqlx::query_as::<
        _,
        (String, Option<String>, String, String, i64, Option<String>, Option<Vec<u8>>),
    >(&sql);
    if let Some(b) = bind {
        q = q.bind(b);
    }
    q.fetch_all(pool)
        .await
        .unwrap_or_default()
        .into_iter()
        .map(|(id, url, title, body, touched_at, referrer, blob)| Row {
            id,
            url,
            title,
            body,
            touched_at,
            referrer,
            vector: blob.map(|b| embed::from_blob(&b)),
        })
        .collect()
}

pub async fn suggest_for_jar<R: Runtime>(
    app: &AppHandle<R>,
    jar_id: &str,
) -> Vec<Suggestion> {
    let Some(pool) = db::sqlite_pool(app).await else {
        return vec![];
    };

    let jar_rows = load_rows(&pool, "i.jar_id = ?1", Some(jar_id)).await;
    if jar_rows.is_empty() {
        return vec![]; // an empty jar has no boundaries to learn yet
    }
    let candidates = load_rows(
        &pool,
        "i.jar_id IS NULL AND i.kind = 'page' AND i.sealed_at IS NULL",
        None,
    )
    .await;
    if candidates.is_empty() {
        return vec![];
    }

    // Correction layer: every verdict the user has already given this jar.
    let feedback: HashMap<String, String> = sqlx::query_as::<_, (String, String)>(
        "SELECT item_id, action FROM suggestion_feedback WHERE jar_id = ?1",
    )
    .bind(jar_id)
    .fetch_all(&pool)
    .await
    .unwrap_or_default()
    .into_iter()
    .collect();

    // The jar's profile: embedding centroid + entity sets + touch times.
    let vectors: Vec<&Vec<f32>> = jar_rows.iter().filter_map(|r| r.vector.as_ref()).collect();
    let centroid: Option<Vec<f32>> = if vectors.is_empty() {
        None
    } else {
        let mut c = vec![0f32; embed::DIM];
        for v in &vectors {
            for (ci, vi) in c.iter_mut().zip(v.iter()) {
                *ci += vi;
            }
        }
        let norm = c.iter().map(|v| v * v).sum::<f32>().sqrt().max(1e-12);
        for ci in c.iter_mut() {
            *ci /= norm;
        }
        Some(c)
    };

    let mut jar_domains: HashSet<String> = HashSet::new();
    let mut jar_tickets: HashSet<String> = HashSet::new();
    let mut jar_repos: HashSet<String> = HashSet::new();
    let mut jar_urls: HashSet<String> = HashSet::new();
    for row in &jar_rows {
        let e = entities(row.url.as_deref(), &row.title, &row.body);
        if let Some(d) = e.domain {
            jar_domains.insert(d);
        }
        jar_tickets.extend(e.tickets);
        jar_repos.extend(e.repos);
        if let Some(u) = &row.url {
            jar_urls.insert(u.clone());
        }
    }
    let jar_times: Vec<i64> = jar_rows.iter().map(|r| r.touched_at).collect();

    let mut out: Vec<Suggestion> = candidates
        .iter()
        .filter(|c| feedback.get(&c.id).map(String::as_str) != Some("accepted"))
        .filter_map(|c| {
            let semantic = match (&centroid, &c.vector) {
                (Some(ctr), Some(v)) => cosine(ctr, v).max(0.0),
                _ => 0.0,
            };
            let e = entities(c.url.as_deref(), &c.title, &c.body);
            let domain_hit = e
                .domain
                .as_ref()
                .is_some_and(|d| jar_domains.contains(d));
            let entity_hit = e.tickets.iter().any(|t| jar_tickets.contains(t))
                || e.repos.iter().any(|r| jar_repos.contains(r));
            let session_hit = jar_times
                .iter()
                .any(|t| (c.touched_at - t).abs() < SESSION_WINDOW_MS);
            let referrer_hit = c.referrer.as_ref().is_some_and(|r| {
                jar_urls.contains(r)
                    || url::Url::parse(r)
                        .ok()
                        .and_then(|u| u.host_str().map(|h| {
                            jar_domains.contains(h.trim_start_matches("www."))
                        }))
                        .unwrap_or(false)
            });
            let rejected = feedback.get(&c.id).map(String::as_str) == Some("rejected");

            let score = W_SEMANTIC * semantic
                + W_DOMAIN * domain_hit as u8 as f32
                + W_ENTITY * entity_hit as u8 as f32
                + W_SESSION * session_hit as u8 as f32
                + W_REFERRER * referrer_hit as u8 as f32
                - W_REJECTED * rejected as u8 as f32;

            (score >= THRESHOLD).then(|| Suggestion {
                item_id: c.id.clone(),
                title: c.title.clone(),
                url: c.url.clone(),
                score,
            })
        })
        .collect();

    out.sort_by(|a, b| b.score.total_cmp(&a.score));
    out.truncate(LIMIT);
    out
}
