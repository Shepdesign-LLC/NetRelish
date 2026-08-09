import { listen } from "@tauri-apps/api/event";
import { useCallback, useEffect, useState } from "react";
import BrineView from "./components/BrineView";
import JarRail, { type JarSummary } from "./components/JarRail";
import TitleBar from "./components/TitleBar";
import { BRINE_CHANGED, brineCount } from "./lib/db";
import {
  hidePreview,
  openPreview,
  showPreview,
  usePreviewHole,
} from "./lib/preview";

function normalizeUrl(input: string): string {
  const trimmed = input.trim();
  if (!trimmed) return "";
  if (/^https?:\/\//i.test(trimmed)) return trimmed;
  if (/^[\w-]+(\.[\w-]+)+(\/|$)/.test(trimmed)) return `https://${trimmed}`;
  return `https://duckduckgo.com/?q=${encodeURIComponent(trimmed)}`;
}

// Week 3 replaces this with real rows from SQLite.
const PLACEHOLDER_JARS: JarSummary[] = [];

export default function App() {
  const [theme] = useState<"dark" | "light">("dark");
  const [activeJarId, setActiveJarId] = useState<string | null>(null);
  const [url, setUrl] = useState("");
  const [loaded, setLoaded] = useState(false);
  const [brineOpen, setBrineOpen] = useState(false);
  const [count, setCount] = useState(0);

  const holeRef = usePreviewHole(loaded);
  const activeJar = PLACEHOLDER_JARS.find((j) => j.id === activeJarId) ?? null;

  // The rail count stays live: refreshed at startup and after every
  // extraction Rust reports.
  useEffect(() => {
    void brineCount().then(setCount);
    let unlisten: (() => void) | undefined;
    let disposed = false;
    void listen(BRINE_CHANGED, () => void brineCount().then(setCount)).then(
      (f) => {
        if (disposed) f();
        else unlisten = f;
      },
    );
    return () => {
      disposed = true;
      unlisten?.();
    };
  }, []);

  const openUrl = useCallback(
    async (target: string) => {
      const box = holeRef.current?.getBoundingClientRect();
      if (!box) return;

      await openPreview(target, {
        x: Math.round(box.left),
        y: Math.round(box.top),
        width: Math.round(box.width),
        height: Math.round(box.height),
      });
      setUrl(target);
      setLoaded(true);
      setBrineOpen(false);
    },
    [holeRef],
  );

  const navigate = useCallback(async () => {
    const target = normalizeUrl(url);
    if (!target) return;
    await openUrl(target);
  }, [url, openUrl]);

  const toggleBrine = useCallback(async () => {
    setActiveJarId(null);
    if (brineOpen) {
      // Back to the page, exactly where it was. Nothing was closed.
      setBrineOpen(false);
      if (loaded) await showPreview();
    } else {
      setBrineOpen(true);
      if (loaded) await hidePreview();
    }
  }, [brineOpen, loaded]);

  return (
    <div className="nr-app" data-nr-theme={theme}>
      <TitleBar
        jarName={activeJar?.name ?? null}
        url={url}
        onUrlChange={setUrl}
        onNavigate={navigate}
      />

      <div className="nr-body">
        <JarRail
          jars={PLACEHOLDER_JARS}
          activeJarId={activeJarId}
          brineCount={count}
          brineActive={brineOpen}
          onSelectJar={setActiveJarId}
          onOpenBrine={() => void toggleBrine()}
        />

        {/* The hole. The native WKWebView is positioned over this rect —
            nothing rendered inside it survives once a page loads. The Brine
            surface only ever shows while that webview is hidden. */}
        <div className="nr-stage" ref={holeRef}>
          {brineOpen ? (
            <BrineView onOpen={(target) => void openUrl(target)} />
          ) : (
            !loaded && (
              <div className="nr-stage__empty">
                <p className="nr-stage__mark">NetRelish</p>
                <p className="nr-stage__hint">
                  Enter an address. Everything you read lands in Brine.
                </p>
              </div>
            )
          )}
        </div>
      </div>
    </div>
  );
}
