/**
 * The tool bridge.
 *
 * Zest, Mise and Scale run as iframes using the same embed protocol as the
 * web build (postMessage + auto-height + theme negotiation). The desktop shell
 * adds exactly one new message type — `nr:export` — which is the whole point
 * of the app: generated files land on disk instead of the clipboard.
 */
import { invoke } from "@tauri-apps/api/core";

export type ToolId = "mise" | "zest" | "scale";

export interface ExportFile {
  /** Project-relative, e.g. "theme/assets/css/_tokens.css" */
  path: string;
  contents: string;
}

export interface WriteReport {
  written: string[];
  backedUp: string[];
}

type InboundMessage =
  | { type: "nr:ready"; tool: ToolId }
  | { type: "nr:height"; height: number }
  | { type: "nr:export"; tool: ToolId; files: ExportFile[] };

export interface BridgeHandlers {
  onReady?(tool: ToolId): void;
  onHeight?(height: number): void;
  /** Return true to accept the write. Show a diff here — never write blind. */
  onExportRequest(tool: ToolId, files: ExportFile[]): Promise<boolean>;
  projectRoot(): string | null;
}

/**
 * Attach the bridge. Returns a detach function.
 *
 * `allowedOrigins` is not optional theatre: an iframe can be navigated, and
 * accepting export instructions from an arbitrary origin would mean any page
 * could write to the user's project directory.
 */
export function attachBridge(
  handlers: BridgeHandlers,
  allowedOrigins: string[],
): () => void {
  const listener = async (event: MessageEvent) => {
    if (!allowedOrigins.includes(event.origin)) return;

    const message = event.data as InboundMessage;
    if (!message || typeof message.type !== "string") return;

    switch (message.type) {
      case "nr:ready":
        handlers.onReady?.(message.tool);
        break;

      case "nr:height":
        handlers.onHeight?.(message.height);
        break;

      case "nr:export": {
        const root = handlers.projectRoot();
        const source = event.source as WindowProxy | null;

        if (!root) {
          source?.postMessage(
            { type: "nr:export:nack", reason: "no-project" },
            event.origin,
          );
          return;
        }

        const approved = await handlers.onExportRequest(
          message.tool,
          message.files,
        );
        if (!approved) {
          source?.postMessage(
            { type: "nr:export:nack", reason: "declined" },
            event.origin,
          );
          return;
        }

        try {
          const report = await writeProjectFiles(root, message.files);
          source?.postMessage({ type: "nr:export:ack", report }, event.origin);
        } catch (error) {
          source?.postMessage(
            { type: "nr:export:nack", reason: String(error) },
            event.origin,
          );
        }
        break;
      }
    }
  };

  window.addEventListener("message", listener);
  return () => window.removeEventListener("message", listener);
}

export function writeProjectFiles(
  projectRoot: string,
  files: ExportFile[],
): Promise<WriteReport> {
  return invoke<WriteReport>("write_project_files", { projectRoot, files });
}

export function readProjectFile(
  projectRoot: string,
  path: string,
): Promise<string | null> {
  return invoke<string | null>("read_project_file", { projectRoot, path });
}
