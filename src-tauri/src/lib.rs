pub mod commands;
pub mod error;

use tauri::Manager;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let mut builder = tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init());

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

            #[cfg(debug_assertions)]
            {
                let _ = &window;
                if let Some(webview) = app.get_webview_window("main") {
                    webview.open_devtools();
                }
            }

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::preview::preview_open,
            commands::preview::preview_set_bounds,
            commands::preview::preview_close,
        ])
        .run(tauri::generate_context!())
        .expect("error while running NetRelish");
}
