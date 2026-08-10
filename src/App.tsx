import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { useCallback, useEffect, useRef, useState } from "react";
import BrineView from "./components/BrineView";
import JarRail from "./components/JarRail";
import JarView from "./components/JarView";
import TitleBar, { OMNIBOX_ID } from "./components/TitleBar";
import {
  BRINE_CHANGED,
  brineCount,
  createJar,
  listJars,
  moveItems,
  type Jar,
} from "./lib/db";
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

/** What the stage shows. Independent of which jar is active — you can look
 *  at Brine while a jar stays open for ⌘J and new pages. */
type View = "page" | "brine" | "jar" | "create";

export default function App() {
  const [theme] = useState<"dark" | "light">("dark");
  const [view, setView] = useState<View>("brine");
  const [activeJarId, setActiveJarId] = useState<string | null>(null);
  const [jars, setJars] = useState<Jar[]>([]);
  const [count, setCount] = useState(0);
  const [url, setUrl] = useState("");
  const [loaded, setLoaded] = useState(false);
  const [status, setStatus] = useState<string | null>(null);
  const [brineSelection, setBrineSelection] = useState<string[]>([]);
  const [refreshToken, setRefreshToken] = useState(0);
  const [draftJarName, setDraftJarName] = useState("");
  const statusTimer = useRef<number | undefined>(undefined);
  const returnView = useRef<View>("brine");

  const holeRef = usePreviewHole(loaded);
  const activeJar = jars.find((j) => j.id === activeJarId) ?? null;

  const showStatus = useCallback((message: string) => {
    setStatus(message);
    window.clearTimeout(statusTimer.current);
    statusTimer.current = window.setTimeout(() => setStatus(null), 3500);
  }, []);

  const refreshShelf = useCallback(async () => {
    const [jarRows, n] = await Promise.all([listJars(), brineCount()]);
    setJars(jarRows);
    setCount(n);
  }, []);

  // The native pane only shows when the stage is actually the page.
  useEffect(() => {
    if (!loaded) return;
    if (view === "page") void showPreview();
    else void hidePreview();
  }, [view, loaded]);

  // Shelf stays live: startup, plus every extraction Rust reports.
  useEffect(() => {
    void refreshShelf();
    let unlisten: (() => void) | undefined;
    let disposed = false;
    void listen(BRINE_CHANGED, () => void refreshShelf()).then((f) => {
      if (disposed) f();
      else unlisten = f;
    });
    return () => {
      disposed = true;
      unlisten?.();
    };
  }, [refreshShelf]);

  // The pane reports where it really is (link clicks, redirects).
  useEffect(() => {
    let unlisten: (() => void) | undefined;
    let disposed = false;
    void listen<string>("preview:navigated", (e) => setUrl(e.payload)).then(
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
      setView("page");
    },
    [holeRef],
  );

  const navigate = useCallback(async () => {
    const target = normalizeUrl(url);
    if (!target) return;
    await openUrl(target);
  }, [url, openUrl]);

  /** ⌘J — the primary gesture. Brine selection first, else the open page. */
  const jarIt = useCallback(async () => {
    if (!activeJar) {
      showStatus("No jar open. Click a jar on the shelf first.");
      return;
    }
    if (view === "brine" && brineSelection.length > 0) {
      await moveItems(brineSelection, activeJar.id);
      const n = brineSelection.length;
      setBrineSelection([]);
      setRefreshToken((t) => t + 1);
      await refreshShelf();
      showStatus(`Jarred ${n} page${n === 1 ? "" : "s"} into ${activeJar.name}`);
      return;
    }
    if (!loaded) {
      showStatus("No page open. Enter an address, or select pages in Brine.");
      return;
    }
    try {
      await invoke("jar_page", { jarId: activeJar.id });
      showStatus(`Jarred into ${activeJar.name}`);
    } catch (e) {
      showStatus(String(e));
    }
  }, [activeJar, view, brineSelection, loaded, refreshShelf, showStatus]);

  // The menu accelerator fires no matter which pane has keyboard focus.
  const jarItRef = useRef(jarIt);
  jarItRef.current = jarIt;
  useEffect(() => {
    let unlisten: (() => void) | undefined;
    let disposed = false;
    void listen("menu:jar-it", () => void jarItRef.current()).then((f) => {
      if (disposed) f();
      else unlisten = f;
    });
    return () => {
      disposed = true;
      unlisten?.();
    };
  }, []);

  const activateJar = useCallback(
    async (id: string) => {
      if (activeJarId !== id) {
        setActiveJarId(id);
        await invoke("set_active_jar", { jarId: id });
        setView("jar");
      } else if (view !== "jar") {
        setView("jar");
      } else {
        // Second click on the jar you're looking at: back to the page.
        // Never deactivate here — silently changing where pages land is
        // exactly the kind of surprise that erodes trust in the jar.
        setView(loaded ? "page" : "brine");
      }
    },
    [activeJarId, view, loaded],
  );

  /** Chip click: stop filing into the jar; new pages land in Brine again. */
  const releaseJar = useCallback(async () => {
    setActiveJarId(null);
    await invoke("set_active_jar", { jarId: null });
    if (view === "jar") setView("brine");
    showStatus("New pages land in Brine");
  }, [view, showStatus]);

  // ⌘L — focus the omnibox (Rust has already pulled keyboard focus back
  // from the page pane to the chrome webview).
  useEffect(() => {
    let unlisten: (() => void) | undefined;
    let disposed = false;
    void listen("menu:open-location", () => {
      const box = document.getElementById(OMNIBOX_ID);
      if (box instanceof HTMLInputElement) {
        box.focus();
        box.select();
      }
    }).then((f) => {
      if (disposed) f();
      else unlisten = f;
    });
    return () => {
      disposed = true;
      unlisten?.();
    };
  }, []);

  const toggleBrine = useCallback(() => {
    if (view === "brine" && loaded) setView("page");
    else setView("brine");
  }, [view, loaded]);

  const submitNewJar = useCallback(async () => {
    const name = draftJarName.trim();
    if (!name) return;
    const jar = await createJar(name);
    setDraftJarName("");
    await refreshShelf();
    setActiveJarId(jar.id);
    await invoke("set_active_jar", { jarId: jar.id });
    setView("jar");
  }, [draftJarName, refreshShelf]);

  const jarDeleted = useCallback(async () => {
    setActiveJarId(null);
    await invoke("set_active_jar", { jarId: null });
    await refreshShelf();
    setRefreshToken((t) => t + 1);
    setView("brine");
    showStatus("Jar deleted. Its items are back in Brine.");
  }, [refreshShelf, showStatus]);

  const stageContent = () => {
    if (view === "brine") {
      return (
        <BrineView
          activeJarName={activeJar?.name ?? null}
          selection={brineSelection}
          refreshToken={refreshToken}
          onSelectionChange={setBrineSelection}
          onOpen={(target) => void openUrl(target)}
          onJarSelection={() => void jarIt()}
        />
      );
    }
    if (view === "jar" && activeJar) {
      return (
        <JarView
          jar={activeJar}
          jars={jars}
          refreshToken={refreshToken}
          onOpen={(target) => void openUrl(target)}
          onChanged={() => {
            setRefreshToken((t) => t + 1);
            void refreshShelf();
          }}
          onDeleted={() => void jarDeleted()}
        />
      );
    }
    if (view === "create") {
      return (
        <div className="nr-newjar">
          <form
            className="nr-newjar__form"
            onSubmit={(e) => {
              e.preventDefault();
              void submitNewJar();
            }}
          >
            <label htmlFor="nr-newjar-name">New jar</label>
            <input
              id="nr-newjar-name"
              value={draftJarName}
              placeholder="What are you working on?"
              autoFocus
              onChange={(e) => setDraftJarName(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Escape") setView(returnView.current);
              }}
            />
            <div className="nr-newjar__actions">
              <button type="submit" disabled={!draftJarName.trim()}>
                Create
              </button>
              <button type="button" onClick={() => setView(returnView.current)}>
                Cancel
              </button>
            </div>
          </form>
        </div>
      );
    }
    if (!loaded) {
      return (
        <div className="nr-stage__empty">
          <p className="nr-stage__mark">NetRelish</p>
          <p className="nr-stage__hint">
            Enter an address. Everything you read lands in Brine.
          </p>
        </div>
      );
    }
    return null;
  };

  return (
    <div className="nr-app" data-nr-theme={theme}>
      <TitleBar
        jarName={activeJar?.name ?? null}
        jarHue={activeJar?.hue ?? null}
        url={url}
        status={status}
        onUrlChange={setUrl}
        onNavigate={() => void navigate()}
        onReleaseJar={() => void releaseJar()}
      />

      <div className="nr-body">
        <JarRail
          jars={jars}
          activeJarId={activeJarId}
          brineCount={count}
          brineActive={view === "brine"}
          onSelectJar={(id) => void activateJar(id)}
          onOpenBrine={toggleBrine}
          onNewJar={() => {
            returnView.current = view === "create" ? "brine" : view;
            setView("create");
          }}
        />

        {/* The hole. The native WKWebView is positioned over this rect —
            nothing rendered inside it survives once a page loads. Chrome
            surfaces only ever show while that webview is hidden. */}
        <div className="nr-stage" ref={holeRef}>
          {stageContent()}
        </div>
      </div>
    </div>
  );
}
