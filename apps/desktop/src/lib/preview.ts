/**
 * Keeps the native child webview glued to the gap the React layout leaves
 * for it.
 *
 * The pane is not a DOM element — it is a separate WKWebView sitting on top of
 * the window. React renders a hole; this hook measures the hole and tells Rust
 * where to put the webview. Get this wrong and the page drifts out from under
 * the chrome on every resize.
 */
import { invoke } from "@tauri-apps/api/core";
import { useEffect, useRef } from "react";

export interface Rect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export function openPreview(url: string, rect: Rect): Promise<void> {
  return invoke("preview_open", { url, rect });
}

export function setPreviewBounds(rect: Rect): Promise<void> {
  return invoke("preview_set_bounds", { rect });
}

export function closePreview(): Promise<void> {
  return invoke("preview_close");
}

/**
 * Hide the native pane so chrome surfaces (Brine) can use the stage.
 * The page and its scroll position survive — hiding is not closing.
 */
export function hidePreview(): Promise<void> {
  return invoke("preview_hide");
}

export function showPreview(): Promise<void> {
  return invoke("preview_show");
}

/** Observe an element and mirror its bounds onto the native pane. */
export function usePreviewHole(active: boolean) {
  const ref = useRef<HTMLDivElement | null>(null);
  const last = useRef<string>("");

  useEffect(() => {
    const node = ref.current;
    if (!node || !active) return;

    const sync = () => {
      const box = node.getBoundingClientRect();
      const rect: Rect = {
        x: Math.round(box.left),
        y: Math.round(box.top),
        width: Math.round(box.width),
        height: Math.round(box.height),
      };
      const key = `${rect.x}:${rect.y}:${rect.width}:${rect.height}`;
      if (key === last.current) return;
      last.current = key;
      void setPreviewBounds(rect);
    };

    const observer = new ResizeObserver(sync);
    observer.observe(node);
    window.addEventListener("resize", sync);
    sync();

    return () => {
      observer.disconnect();
      window.removeEventListener("resize", sync);
    };
  }, [active]);

  return ref;
}
