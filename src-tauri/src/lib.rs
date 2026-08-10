pub mod commands;
pub mod db;
pub mod denylist;
pub mod error;
pub mod extract;

use tauri::menu::{Menu, MenuItemBuilder, SubmenuBuilder};
use tauri::{Emitter, Manager};
use tauri_plugin_sql::{Migration, MigrationKind};

/// Applied in order at startup (the database is preloaded, see
/// tauri.conf.json > plugins > sql). Shipped migrations are never edited —
/// schema changes get a new NNN file.
fn migrations() -> Vec<Migration> {
    vec![Migration {
        version: 1,
        description: "init",
        sql: include_str!("../migrations/001_init.sql"),
        kind: MigrationKind::Up,
    }]
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let mut builder = tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(
            tauri_plugin_sql::Builder::default()
                .add_migrations(db::DB_URL, migrations())
                .build(),
        );

    #[cfg(desktop)]
    {
        builder = builder.plugin(tauri_plugin_updater::Builder::new().build());
    }

    builder
        .setup(|app| {
            let window = app
                .get_window("main")
                .expect("main window is declared in tauri.conf.json");

            // Traffic lights sit on the chrome itself. The React titlebar
            // reserves 78px on the left so they never collide with UI.
            #[cfg(target_os = "macos")]
            {
                use tauri::TitleBarStyle;
                let _ = window.set_title_bar_style(TitleBarStyle::Overlay);
            }

            // Opt-in via NR_DEVTOOLS=1: the inspector docks into the main
            // window and steals focus, which gets in the way of normal dev
            // runs (and of scripted UI testing).
            #[cfg(debug_assertions)]
            {
                let _ = &window;
                if std::env::var("NR_DEVTOOLS").is_ok_and(|v| v == "1") {
                    if let Some(webview) = app.get_webview_window("main") {
                        webview.open_devtools();
                    }
                }
            }

            let _ = denylist::ensure_default(app.handle());
            app.manage(db::ActiveJar::default());

            // ⌘J must work while the native page pane has keyboard focus,
            // where DOM listeners in the chrome never hear it. A real menu
            // item is the macOS-native answer: the menu system claims the
            // key before either webview sees it.
            {
                let jar_item = MenuItemBuilder::with_id("jar-it", "Jar This Page")
                    .accelerator("CmdOrCtrl+J")
                    .build(app)?;
                let open_location = MenuItemBuilder::with_id("open-location", "Open Location…")
                    .accelerator("CmdOrCtrl+L")
                    .build(app)?;
                let submenu = SubmenuBuilder::new(app, "Jars")
                    .item(&jar_item)
                    .separator()
                    .item(&open_location)
                    .build()?;
                match app.menu() {
                    Some(menu) => menu.append(&submenu)?,
                    None => {
                        let menu = Menu::default(app.handle())?;
                        menu.append(&submenu)?;
                        app.set_menu(menu)?;
                    }
                }
            }

            // Dev affordance, absent from release builds: NR_DEV_OPEN_URL
            // opens the preview straight to a page so the extraction
            // pipeline can be exercised without driving the UI.
            #[cfg(debug_assertions)]
            if let Ok(dev_url) = std::env::var("NR_DEV_OPEN_URL") {
                let window = window.clone();
                std::thread::spawn(move || {
                    std::thread::sleep(std::time::Duration::from_millis(800));
                    let rect = commands::preview::Rect {
                        x: 56.0,
                        y: 44.0,
                        width: 900.0,
                        height: 620.0,
                    };
                    if let Err(e) = tauri::async_runtime::block_on(
                        commands::preview::preview_open(window, dev_url, rect),
                    ) {
                        eprintln!("dev open failed: {e}");
                    }
                });
            }

            // WAL survives a force-quit mid-write; sqlx leaves the journal
            // mode alone by default. The pragma is persistent — stored in
            // the database file — so once is enough, but re-running it every
            // launch is free and covers databases created before this line.
            let handle = app.handle().clone();
            tauri::async_runtime::spawn(async move {
                if let Some(pool) = db::sqlite_pool(&handle).await {
                    // fetch_optional: the pragma answers with one row.
                    if let Err(e) = sqlx::query("PRAGMA journal_mode=WAL;")
                        .fetch_optional(&pool)
                        .await
                    {
                        eprintln!("db: WAL pragma failed: {e}");
                    }
                } else {
                    eprintln!("db: pool missing at setup; preload misconfigured?");
                }
            });

            Ok(())
        })
        .on_menu_event(|app, event| {
            if event.id() == "jar-it" {
                // The frontend owns the decision of what "it" is — the
                // current page, or the Brine selection as a Batch.
                let _ = app.emit_to("main", "menu:jar-it", ());
            } else if event.id() == "open-location" {
                // The page pane may hold the keyboard. Hand the native
                // first-responder back to the chrome webview, then let the
                // frontend focus the omnibox itself.
                if let Some(chrome) = app
                    .get_window("main")
                    .and_then(|w| w.get_webview("main"))
                {
                    let _ = chrome.set_focus();
                }
                let _ = app.emit_to("main", "menu:open-location", ());
            }
        })
        .invoke_handler(tauri::generate_handler![
            commands::preview::preview_open,
            commands::preview::preview_set_bounds,
            commands::preview::preview_close,
            commands::preview::preview_hide,
            commands::preview::preview_show,
            commands::denylist::denylist_get,
            commands::denylist::denylist_set,
            commands::jars::set_active_jar,
            commands::jars::jar_page,
        ])
        .run(tauri::generate_context!())
        .expect("error while running NetRelish");
}
