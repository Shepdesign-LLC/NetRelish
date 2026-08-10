import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { useCallback, useEffect, useRef, useState } from "react";
import BrineView from "./components/BrineView";
import JarRail from "./components/JarRail";
import JarView from "./components/JarView";
import Palette from "./components/Palette";
import RunnerBar from "./components/RunnerBar";
import TabStrip from "./components/TabStrip";
import TitleBar, { OMNIBOX_ID, type Status } from "./components/TitleBar";
import { normalizeUrl, parseDenyList } from "./lib/format";
import { interpolate, parseSteps, type RecipeStep } from "./lib/recipes";
import {
  BRINE_CHANGED,
  brineCount,
  createJar,
  createNoteItem,
  createRecipe,
  lastSealedScroll,
  listJars,
  listRecipes,
  moveItems,
  purgeExpiredSweeps,
  sweepDue,
  tabClose,
  tabCreate,
  tabSetPinned,
  tabSetScroll,
  tabTouch,
  tabsList,
  undoSweep,
  unsealUrl,
  type Jar,
  type Recipe,
  type Tab,
} from "./lib/db";
import {
  hidePreview,
  openPreview,
  showPreview,
  usePreviewHole,
} from "./lib/preview";

/** What the stage shows. Independent of which jar is active — you can look
 *  at Brine while a jar stays open for ⌘J and new pages. */
type View = "page" | "brine" | "jar" | "create";

/** A recipe run in progress. */
interface RunState {
  recipe: Recipe;
  steps: RecipeStep[];
  index: number;
  finished: boolean;
  executed: number[];
  openedTabs: string[];
  split: boolean;
}

export default function App() {
  const [theme] = useState<"dark" | "light">("dark");
  const [view, setView] = useState<View>("brine");
  const [activeJarId, setActiveJarId] = useState<string | null>(null);
  const [jars, setJars] = useState<Jar[]>([]);
  const [count, setCount] = useState(0);
  const [tabs, setTabs] = useState<Tab[]>([]);
  const [activeTabId, setActiveTabId] = useState<string | null>(null);
  const [sealingIds, setSealingIds] = useState<string[]>([]);
  const [url, setUrl] = useState("");
  const [loaded, setLoaded] = useState(false);
  const [status, setStatus] = useState<Status | null>(null);
  const [brineSelection, setBrineSelection] = useState<string[]>([]);
  const [refreshToken, setRefreshToken] = useState(0);
  const [draftJarName, setDraftJarName] = useState("");
  const [paletteOpen, setPaletteOpen] = useState(false);
  // Palette input lives here so Escape never loses what was typed.
  const [paletteQuery, setPaletteQuery] = useState("");
  // The recorder: null when off; while on, chrome-initiated actions append.
  const [recordedSteps, setRecordedSteps] = useState<RecipeStep[] | null>(null);
  const [run, setRun] = useState<RunState | null>(null);
  const runRef = useRef<RunState | null>(null);
  runRef.current = run;
  const statusTimer = useRef<number | undefined>(undefined);
  const returnView = useRef<View>("brine");
  // Scroll to restore once the pane reports the navigation finished.
  const pendingScroll = useRef<number | null>(null);

  const holeRef = usePreviewHole(loaded);
  const activeJar = jars.find((j) => j.id === activeJarId) ?? null;
  const activeTab = tabs.find((t) => t.id === activeTabId) ?? null;

  const showStatus = useCallback((s: Status, holdMs = 3500) => {
    setStatus(s);
    window.clearTimeout(statusTimer.current);
    statusTimer.current = window.setTimeout(() => setStatus(null), holdMs);
  }, []);

  const refreshShelf = useCallback(async () => {
    const [jarRows, n] = await Promise.all([listJars(), brineCount()]);
    setJars(jarRows);
    setCount(n);
  }, []);

  const refreshTabs = useCallback(async () => {
    setTabs(await tabsList());
  }, []);

  // The native pane only shows when the stage is the page of a tab that
  // actually has one, with no chrome surface (the palette) over it.
  useEffect(() => {
    if (!loaded) return;
    if (view === "page" && !paletteOpen && activeTab?.url) void showPreview();
    else void hidePreview();
  }, [view, loaded, paletteOpen, activeTab]);

  /* ------------------------------------------------------------------ */
  /* Tabs                                                                */

  const openUrl = useCallback(
    async (target: string, opts?: { newTab?: boolean }): Promise<string | null> => {
      const box = holeRef.current?.getBoundingClientRect();
      if (!box) return null;

      // The recorder hears where YOU point the browser — chrome-initiated
      // opens only, and never the runner's own steps.
      if (!runRef.current) {
        setRecordedSteps((s) => (s ? [...s, { kind: "open", url: target }] : s));
      }

      let tab = tabs.find((t) => t.id === activeTabId) ?? null;
      if (opts?.newTab || !tab) {
        tab = await tabCreate(activeJarId, target);
        setActiveTabId(tab.id);
      } else {
        await tabTouch(tab.id, target, tab.jar_id);
      }

      // Reopening something sealed restores where the reader left off and
      // makes it live again. For never-sealed pages both are no-ops.
      pendingScroll.current = await lastSealedScroll(target);
      await unsealUrl(target);

      await openPreview(target, {
        x: Math.round(box.left),
        y: Math.round(box.top),
        width: Math.round(box.width),
        height: Math.round(box.height),
      });
      setUrl(target);
      setLoaded(true);
      setView("page");
      setRefreshToken((t) => t + 1);
      await refreshTabs();
      return tab.id;
    },
    [holeRef, tabs, activeTabId, activeJarId, refreshTabs],
  );

  const switchTab = useCallback(
    async (id: string) => {
      if (id === activeTabId) {
        setView("page");
        return;
      }
      // Preserve the outgoing tab's exact place before leaving it.
      if (activeTab?.url && loaded) {
        const y = await invoke<number>("preview_get_scroll");
        await tabSetScroll(activeTab.id, y);
      }
      const next = tabs.find((t) => t.id === id);
      if (!next) return;
      setActiveTabId(id);
      if (next.url) {
        const box = holeRef.current?.getBoundingClientRect();
        if (!box) return;
        pendingScroll.current = next.scroll_y;
        await openPreview(next.url, {
          x: Math.round(box.left),
          y: Math.round(box.top),
          width: Math.round(box.width),
          height: Math.round(box.height),
        });
        setUrl(next.url);
        setLoaded(true);
      } else {
        setUrl("");
        await hidePreview();
      }
      setView("page");
    },
    [activeTabId, activeTab, tabs, loaded, holeRef],
  );

  const newTab = useCallback(async () => {
    const tab = await tabCreate(activeJarId, null);
    setActiveTabId(tab.id);
    setUrl("");
    setView("page");
    await hidePreview();
    await refreshTabs();
    document.getElementById(OMNIBOX_ID)?.focus();
  }, [activeJarId, refreshTabs]);

  const closeTab = useCallback(
    async (id: string) => {
      await tabClose(id);
      const remaining = tabs.filter((t) => t.id !== id);
      setTabs(remaining);
      if (id === activeTabId) {
        const closedIndex = tabs.findIndex((t) => t.id === id);
        const next = remaining[closedIndex] ?? remaining[closedIndex - 1] ?? null;
        if (next) await switchTab(next.id);
        else {
          setActiveTabId(null);
          setUrl("");
          await hidePreview();
          setView("brine");
        }
      }
    },
    [tabs, activeTabId, switchTab],
  );

  const togglePin = useCallback(
    async (tab: Tab) => {
      await tabSetPinned(tab.id, tab.jar_id, tab.seal_after !== null);
      await refreshTabs();
    },
    [refreshTabs],
  );

  /* ------------------------------------------------------------------ */
  /* Sealing                                                             */

  const undoBatch = useCallback(
    async (batchId: string) => {
      const restored = await undoSweep(batchId);
      await refreshTabs();
      await refreshShelf();
      setRefreshToken((t) => t + 1);
      showStatus({
        text: `Restored ${restored} tab${restored === 1 ? "" : "s"}`,
      });
    },
    [refreshTabs, refreshShelf, showStatus],
  );

  const sweep = useCallback(async () => {
    await purgeExpiredSweeps();
    const deny = parseDenyList(await invoke<string>("denylist_get"));
    const result = await sweepDue(deny);
    if (!result) return;

    // Let the strip play the tabs shut before they leave the list.
    setSealingIds(result.sealedTabIds);
    window.setTimeout(() => {
      void (async () => {
        setSealingIds([]);
        await refreshTabs();
        await refreshShelf();
        setRefreshToken((t) => t + 1);
        if (activeTabId && result.sealedTabIds.includes(activeTabId)) {
          setActiveTabId(null);
          setUrl("");
          await hidePreview();
          setView("brine");
        }
      })();
    }, 300);

    const into =
      result.jarNames.length === 1
        ? (result.jarNames[0] || "Brine")
        : "their jars";
    showStatus(
      {
        text: `Sealed ${result.count} tab${result.count === 1 ? "" : "s"} into ${into}`,
        action: { label: "Undo", run: () => void undoBatch(result.batchId) },
      },
      15_000,
    );
  }, [activeTabId, refreshTabs, refreshShelf, showStatus, undoBatch]);

  // Sweep on launch and hourly. The sweep itself is set-based SQL; 200
  // tabs is four statements, not four hundred.
  const sweepRef = useRef(sweep);
  sweepRef.current = sweep;
  useEffect(() => {
    const t = window.setTimeout(() => void sweepRef.current(), 2500);
    const interval = window.setInterval(
      () => void sweepRef.current(),
      3_600_000,
    );
    return () => {
      window.clearTimeout(t);
      window.clearInterval(interval);
    };
  }, []);

  /* ------------------------------------------------------------------ */
  /* Recipes: recorder + runner                                          */

  const openUrlRef = useRef(openUrl);
  openUrlRef.current = openUrl;

  /** Perform one action step. Task steps perform nothing — they wait. */
  const executeStep = useCallback(
    async (state: RunState, index: number): Promise<RunState> => {
      const step = state.steps[index];
      const ctx = {
        jar: jars.find((j) => j.id === activeJarId)?.name ?? "Brine",
        url,
      };
      const next = { ...state, executed: [...state.executed, index] };
      switch (step.kind) {
        case "open": {
          const tabId = await openUrlRef.current(interpolate(step.url, ctx), {
            newTab: true,
          });
          if (tabId) next.openedTabs = [...next.openedTabs, tabId];
          break;
        }
        case "split": {
          const box = holeRef.current?.getBoundingClientRect();
          if (box) {
            await invoke("preview_split", {
              left: interpolate(step.left, ctx),
              right: interpolate(step.right, ctx),
              rect: {
                x: Math.round(box.left),
                y: Math.round(box.top),
                width: Math.round(box.width),
                height: Math.round(box.height),
              },
            });
            setUrl(interpolate(step.left, ctx));
            setLoaded(true);
            setView("page");
            next.split = true;
          }
          break;
        }
        case "note":
          await createNoteItem(activeJarId, interpolate(step.text, ctx));
          setRefreshToken((t) => t + 1);
          break;
        case "collect":
          if (activeJarId) {
            await invoke("jar_page", { jarId: activeJarId }).catch(() => {});
          }
          break;
        case "seal": {
          for (const id of next.openedTabs) {
            await tabClose(id);
          }
          next.openedTabs = [];
          await refreshTabs();
          break;
        }
        case "task":
          break;
      }
      return next;
    },
    [jars, activeJarId, url, holeRef, refreshTabs],
  );

  /** Advance from `from`, auto-running action steps until a task or the
   *  end. Steps run at most once; Back never re-fires them. */
  const advanceRun = useCallback(
    async (state: RunState, from: number): Promise<void> => {
      let s = state;
      let i = from;
      while (i + 1 < s.steps.length) {
        i += 1;
        s = { ...s, index: i };
        if (s.steps[i].kind === "task") {
          setRun(s);
          return;
        }
        if (!s.executed.includes(i)) {
          setRun(s); // show the step as it happens
          s = await executeStep(s, i);
          await new Promise((r) => setTimeout(r, 350));
        }
      }
      setRun({ ...s, finished: true });
    },
    [executeStep],
  );

  const startRun = useCallback(
    async (recipe: Recipe) => {
      const parsed = parseSteps(recipe.steps);
      if (typeof parsed === "string") {
        showStatus({ text: `Recipe won't run: ${parsed}` });
        return;
      }
      if (parsed.length === 0) {
        showStatus({ text: "This recipe has no steps yet." });
        return;
      }
      const state: RunState = {
        recipe,
        steps: parsed,
        index: -1,
        finished: false,
        executed: [],
        openedTabs: [],
        split: false,
      };
      setRun(state);
      await advanceRun(state, -1);
    },
    [advanceRun, showStatus],
  );

  const unsplitNow = useCallback(async () => {
    const box = holeRef.current?.getBoundingClientRect();
    if (!box) return;
    await invoke("preview_unsplit", {
      rect: {
        x: Math.round(box.left),
        y: Math.round(box.top),
        width: Math.round(box.width),
        height: Math.round(box.height),
      },
    }).catch(() => {});
  }, [holeRef]);

  /** Finish keeps everything the run made; only the split closes. */
  const finishRun = useCallback(async () => {
    const s = runRef.current;
    if (s?.split) await unsplitNow();
    setRun(null);
  }, [unsplitNow]);

  /** Cancel undoes the run's presence: its tabs close (their pages stay
   *  preserved — closing is free), the split closes. Completed notes are
   *  whole, not half-written, and remain. */
  const cancelRun = useCallback(async () => {
    const s = runRef.current;
    if (!s) return;
    for (const id of s.openedTabs) {
      await tabClose(id);
    }
    if (s.split) await unsplitNow();
    await refreshTabs();
    setRun(null);
    showStatus({ text: "Recipe cancelled. Its tabs are closed; nothing is lost." });
  }, [unsplitNow, refreshTabs, showStatus]);

  const runnerDone = useCallback(async () => {
    const s = runRef.current;
    if (s) await advanceRun(s, s.index);
  }, [advanceRun]);

  const runnerBack = useCallback(() => {
    setRun((s) => (s && s.index > 0 ? { ...s, index: s.index - 1, finished: false } : s));
  }, []);

  const startRecording = useCallback(() => {
    setRecordedSteps([]);
    showStatus({ text: "Recording. Work normally; save from the jar's Recipes panel." });
  }, [showStatus]);

  const saveRecording = useCallback(
    async (name: string) => {
      if (!activeJarId || recordedSteps === null) return;
      await createRecipe(activeJarId, name, JSON.stringify(recordedSteps, null, 2));
      setRecordedSteps(null);
      setRefreshToken((t) => t + 1);
      showStatus({ text: `Recipe “${name}” saved` });
    },
    [activeJarId, recordedSteps, showStatus],
  );

  // ⌘R — run the active jar's recipe.
  const runShortcutRef = useRef(() => {});
  runShortcutRef.current = () => {
    void (async () => {
      if (!activeJarId) {
        showStatus({ text: "No jar open. Click a jar on the shelf first." });
        return;
      }
      const recipes = await listRecipes(activeJarId);
      if (recipes.length === 1) void startRun(recipes[0]);
      else if (recipes.length === 0)
        showStatus({ text: "No recipe in this jar yet. Record one from its Recipes panel." });
      else {
        setView("jar");
        showStatus({ text: `${recipes.length} recipes here — run one from the panel.` });
      }
    })();
  };
  useEffect(() => {
    let unlisten: (() => void) | undefined;
    let disposed = false;
    void listen("menu:run-recipe", () => runShortcutRef.current()).then((f) => {
      if (disposed) f();
      else unlisten = f;
    });
    return () => {
      disposed = true;
      unlisten?.();
    };
  }, []);

  /* ------------------------------------------------------------------ */
  /* Startup & listeners                                                 */

  // Shelf, tabs, and the restored session: the most recently touched tab
  // comes back exactly as it was left.
  useEffect(() => {
    void (async () => {
      await refreshShelf();
      const rows = await tabsList();
      setTabs(rows);
      if (rows.length > 0) {
        const recent = [...rows].sort((a, b) => b.touched_at - a.touched_at)[0];
        setActiveTabId(recent.id);
        if (recent.url) {
          const box = holeRef.current?.getBoundingClientRect();
          if (box) {
            pendingScroll.current = recent.scroll_y;
            await openPreview(recent.url, {
              x: Math.round(box.left),
              y: Math.round(box.top),
              width: Math.round(box.width),
              height: Math.round(box.height),
            });
            setUrl(recent.url);
            setLoaded(true);
            setView("page");
          }
        }
      }
    })();
    let unlisten: (() => void) | undefined;
    let disposed = false;
    void listen(BRINE_CHANGED, () => {
      void refreshShelf();
      void refreshTabs(); // titles resolve once extraction lands
    }).then((f) => {
      if (disposed) f();
      else unlisten = f;
    });
    return () => {
      disposed = true;
      unlisten?.();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // The pane reports where it really is (link clicks, redirects). Restore
  // any pending scroll, and let the active tab follow the page.
  const navigatedRef = useRef((_: string) => {});
  navigatedRef.current = (target: string) => {
    setUrl(target);
    if (pendingScroll.current !== null && pendingScroll.current > 0) {
      void invoke("preview_set_scroll", { y: pendingScroll.current });
    }
    pendingScroll.current = null;
    if (activeTab) {
      void tabTouch(activeTab.id, target, activeTab.jar_id).then(refreshTabs);
    }
  };
  useEffect(() => {
    let unlisten: (() => void) | undefined;
    let disposed = false;
    void listen<string>("preview:navigated", (e) =>
      navigatedRef.current(e.payload),
    ).then((f) => {
      if (disposed) f();
      else unlisten = f;
    });
    return () => {
      disposed = true;
      unlisten?.();
    };
  }, []);

  // Menu events: ⌘T, ⌘L, ⌘K, ⌘J.
  const newTabRef = useRef(newTab);
  newTabRef.current = newTab;
  useEffect(() => {
    let unlisten: (() => void) | undefined;
    let disposed = false;
    void listen("menu:new-tab", () => void newTabRef.current()).then((f) => {
      if (disposed) f();
      else unlisten = f;
    });
    return () => {
      disposed = true;
      unlisten?.();
    };
  }, []);

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

  // ⌘K — Ask the Pantry. The menu accelerator covers the case where the
  // native page pane holds the keyboard; the DOM listener covers the chrome.
  // macOS gives the menu first claim, so normally only one path fires — the
  // debounce makes double-fire impossible rather than merely unlikely.
  const lastPaletteToggle = useRef(0);
  useEffect(() => {
    const toggle = () => {
      const now = performance.now();
      if (now - lastPaletteToggle.current < 150) return;
      lastPaletteToggle.current = now;
      setPaletteOpen((o) => !o);
    };
    const onKey = (event: KeyboardEvent) => {
      if (event.metaKey && event.key.toLowerCase() === "k") {
        event.preventDefault();
        toggle();
      }
    };
    // DOM path first: it must survive even where the Tauri bridge is
    // absent (plain-browser dev), and listen() throws there.
    window.addEventListener("keydown", onKey);
    let unlisten: (() => void) | undefined;
    let disposed = false;
    void listen("menu:ask-pantry", toggle).then((f) => {
      if (disposed) f();
      else unlisten = f;
    });
    return () => {
      disposed = true;
      unlisten?.();
      window.removeEventListener("keydown", onKey);
    };
  }, []);

  /* ------------------------------------------------------------------ */
  /* Jars & navigation                                                   */

  const navigate = useCallback(async () => {
    const target = normalizeUrl(url);
    if (!target) return;
    await openUrl(target);
  }, [url, openUrl]);

  /** ⌘J — the primary gesture. Brine selection first, else the open page. */
  const jarIt = useCallback(async () => {
    if (!activeJar) {
      showStatus({ text: "No jar open. Click a jar on the shelf first." });
      return;
    }
    if (view === "brine" && brineSelection.length > 0) {
      await moveItems(brineSelection, activeJar.id);
      const n = brineSelection.length;
      setBrineSelection([]);
      setRefreshToken((t) => t + 1);
      await refreshShelf();
      showStatus({
        text: `Jarred ${n} page${n === 1 ? "" : "s"} into ${activeJar.name}`,
      });
      return;
    }
    if (!loaded || !activeTab?.url) {
      showStatus({
        text: "No page open. Enter an address, or select pages in Brine.",
      });
      return;
    }
    try {
      await invoke("jar_page", { jarId: activeJar.id });
      if (!runRef.current) {
        setRecordedSteps((s) => (s ? [...s, { kind: "collect" }] : s));
      }
      showStatus({ text: `Jarred into ${activeJar.name}` });
    } catch (e) {
      showStatus({ text: String(e) });
    }
  }, [
    activeJar,
    view,
    brineSelection,
    loaded,
    activeTab,
    refreshShelf,
    showStatus,
  ]);

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

  // ⌘1–⌘9 — switch to a jar by shelf position. The menu covers page-pane
  // focus; the DOM listener covers the chrome.
  const jarsRef = useRef(jars);
  jarsRef.current = jars;
  const activateJarRef = useRef((_id: string) => Promise.resolve());
  useEffect(() => {
    const byIndex = (n: number) => {
      const jar = jarsRef.current[n - 1];
      if (jar) void activateJarRef.current(jar.id);
    };
    const onKey = (event: KeyboardEvent) => {
      const n = Number(event.key);
      if (event.metaKey && !event.shiftKey && !event.altKey && n >= 1 && n <= 9) {
        event.preventDefault();
        byIndex(n);
      }
    };
    window.addEventListener("keydown", onKey);
    let unlisten: (() => void) | undefined;
    let disposed = false;
    void listen<number>("menu:switch-jar", (e) => byIndex(e.payload)).then(
      (f) => {
        if (disposed) f();
        else unlisten = f;
      },
    );
    return () => {
      disposed = true;
      unlisten?.();
      window.removeEventListener("keydown", onKey);
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
        setView(loaded && activeTab?.url ? "page" : "brine");
      }
    },
    [activeJarId, view, loaded, activeTab],
  );
  activateJarRef.current = activateJar;

  /** Chip click: stop filing into the jar; new pages land in Brine again. */
  const releaseJar = useCallback(async () => {
    setActiveJarId(null);
    await invoke("set_active_jar", { jarId: null });
    if (view === "jar") setView("brine");
    showStatus({ text: "New pages land in Brine" });
  }, [view, showStatus]);

  const toggleBrine = useCallback(() => {
    if (view === "brine" && loaded && activeTab?.url) setView("page");
    else setView("brine");
  }, [view, loaded, activeTab]);

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
    showStatus({ text: "Jar deleted. Its items are back in Brine." });
  }, [refreshShelf, showStatus]);

  /* ------------------------------------------------------------------ */

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
          onUndoSweep={(batchId) => void undoBatch(batchId)}
        />
      );
    }
    if (view === "jar" && activeJar) {
      return (
        <JarView
          jar={activeJar}
          jars={jars}
          refreshToken={refreshToken}
          recording={recordedSteps !== null}
          onOpen={(target) => void openUrl(target)}
          onChanged={() => {
            setRefreshToken((t) => t + 1);
            void refreshShelf();
          }}
          onDeleted={() => void jarDeleted()}
          onStartRecording={startRecording}
          onSaveRecording={saveRecording}
          onDiscardRecording={() => setRecordedSteps(null)}
          onRunRecipe={(r) => void startRun(r)}
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
    if (!activeTab?.url) {
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

      {run && (
        <RunnerBar
          recipeName={run.recipe.name}
          steps={run.steps}
          index={Math.max(run.index, 0)}
          finished={run.finished}
          onBack={runnerBack}
          onSkip={() => void runnerDone()}
          onDone={() => void runnerDone()}
          onFinish={() => void finishRun()}
          onCancel={() => void cancelRun()}
        />
      )}

      {tabs.length > 0 && (
        <TabStrip
          tabs={tabs}
          activeTabId={activeTabId}
          sealingIds={sealingIds}
          onSelect={(id) => void switchTab(id)}
          onClose={(id) => void closeTab(id)}
          onTogglePin={(tab) => void togglePin(tab)}
          onNewTab={() => void newTab()}
        />
      )}

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

        {/* Sibling of .nr-stage by design (§11): it must never render
            inside the hole the native pane covers. */}
        {paletteOpen && (
          <Palette
            query={paletteQuery}
            activeJarId={activeJarId}
            onQueryChange={setPaletteQuery}
            onOpen={(target, keepOpen) => {
              void openUrl(target);
              if (!keepOpen) setPaletteOpen(false);
            }}
            onClose={() => setPaletteOpen(false)}
          />
        )}
      </div>
    </div>
  );
}
