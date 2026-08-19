//! sqlite-vec must be present on every connection the app opens — the
//! auto-extension is registered before any pool exists (lib.rs).

#[tokio::test]
async fn vec_distance_works_on_fresh_connections() {
    unsafe {
        libsqlite3_sys::sqlite3_auto_extension(Some(std::mem::transmute(
            sqlite_vec::sqlite3_vec_init as *const (),
        )));
    }
    let pool = sqlx::sqlite::SqlitePoolOptions::new()
        .connect("sqlite::memory:")
        .await
        .expect("open in-memory db");

    let a: Vec<u8> = [1f32, 0.0, 0.0].iter().flat_map(|v| v.to_le_bytes()).collect();
    let b: Vec<u8> = [0f32, 1.0, 0.0].iter().flat_map(|v| v.to_le_bytes()).collect();
    let (d,): (f64,) = sqlx::query_as("SELECT vec_distance_cosine(?1, ?2)")
        .bind(&a)
        .bind(&b)
        .fetch_one(&pool)
        .await
        .expect("vec_distance_cosine available");
    assert!((d - 1.0).abs() < 1e-6, "orthogonal vectors → cosine distance 1, got {d}");
}
