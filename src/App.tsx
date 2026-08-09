import { useCallback, useEffect, useState } from "react";
import { open as openDialog } from "@tauri-apps/plugin-dialog";
import PantryRail from "./components/PantryRail";
import TitleBar from "./components/TitleBar";
import ToolPanel, { TOOL_ORIGINS } from "./components/ToolPanel";
import { attachBridge, type ExportFile, type ToolId } from "./lib/bridge";
import { openPreview, usePreviewHole } from "./lib/preview";

function normalizeUrl(input: string): string {
  const trimmed = input.trim();
  if (!trimmed) return "";
  if (/^https?:\/\//i.test(trimmed)) return trimmed;
  if (/^[\w-]+(\.[\w-]+)+(\/|$)/.test(trimmed)) return `https://${trimmed}`;
  return `https://duckduckgo.com/?q=${encodeURIComponent(trimmed)}`;
}

export default function App() {
  const [theme] = useState<"dark" | "light">("dark");
  const [activeTool, setActiveTool] = useState<ToolId | null>("mise");
  const [projectRoot, setProjectRoot] = useState<string | null>(null);
  const [url, setUrl] = useState("");
  const [loaded, setLoaded] = useState(false);

  const holeRef = usePreviewHole(loaded);
  const projectName = projectRoot?.split("/").filter(Boolean).pop() ?? null;

  const pickProject = useCallback(async () => {
    const chosen = await openDialog({
      directory: true,
      multiple: false,
      title: "Choose a project folder",
    });
    if (typeof chosen === "string") setProjectRoot(chosen);
  }, []);

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

  // Week 4 replaces the confirm() with a real diff sheet. The seam is here so
  // the tools can be wired against it now.
  useEffect(() => {
    return attachBridge(
      {
        projectRoot: () => projectRoot,
        async onExportRequest(tool: ToolId, files: ExportFile[]) {
          const list = files.map((f) => `  ${f.path}`).join("\n");
          return window.confirm(
            `${tool} wants to write ${files.length} file(s) into ${projectName}:\n\n${list}`,
          );
        },
      },
      TOOL_ORIGINS,
    );
  }, [projectRoot, projectName]);

  return (
    <div className="nr-app" data-nr-theme={theme}>
      <TitleBar
        projectName={projectName}
        url={url}
        onUrlChange={setUrl}
        onNavigate={navigate}
        onPickProject={pickProject}
      />

      <div className="nr-body">
        <PantryRail active={activeTool} onSelect={setActiveTool} />

        {activeTool && (
          <ToolPanel
            tool={activeTool}
            theme={theme}
            projectName={projectName}
          />
        )}

        {/* The hole. The native WKWebView is positioned over this rect —
            nothing rendered inside it will ever be visible once a page loads. */}
        <div className="nr-stage" ref={holeRef}>
          {!loaded && (
            <div className="nr-stage__empty">
              <p className="nr-stage__mark">NetRelish</p>
              <p className="nr-stage__hint">
                {projectRoot
                  ? "Enter an address to start browsing."
                  : "Open a project folder, then enter an address."}
              </p>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
