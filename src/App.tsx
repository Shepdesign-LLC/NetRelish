import { useCallback, useState } from "react";
import JarRail, { type JarSummary } from "./components/JarRail";
import TitleBar from "./components/TitleBar";
import { openPreview, usePreviewHole } from "./lib/preview";

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

  const holeRef = usePreviewHole(loaded);
  const activeJar = PLACEHOLDER_JARS.find((j) => j.id === activeJarId) ?? null;

  const navigate = useCallback(async () => {
    const target = normalizeUrl(url);
    if (!target) return;
    const box = holeRef.current?.getBoundingClientRect();
    if (!box) return;

    await openPreview(target, {
      x: Math.round(box.left),
      y: Math.round(box.top),
      width: Math.round(box.width),
      height: Math.round(box.height),
    });
    setLoaded(true);
  }, [url, holeRef]);

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
          brineCount={0}
          onSelectJar={setActiveJarId}
          onOpenBrine={() => setActiveJarId(null)}
        />

        {/* The hole. The native WKWebView is positioned over this rect —
            nothing rendered inside it survives once a page loads. */}
        <div className="nr-stage" ref={holeRef}>
          {!loaded && (
            <div className="nr-stage__empty">
              <p className="nr-stage__mark">NetRelish</p>
              <p className="nr-stage__hint">
                Enter an address. Everything you read lands in Brine.
              </p>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
