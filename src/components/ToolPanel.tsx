import type { ToolId } from "../lib/bridge";

/**
 * In development the tools load from localhost. In a release build these point
 * at the hosted Pantry embeds. Both origins must appear in TOOL_ORIGINS or the
 * bridge will ignore their messages.
 */
const DEV = import.meta.env.DEV;

export const TOOL_ORIGIN = DEV ? "http://localhost:5273" : "https://tools.netrelish.com";

export const TOOL_ORIGINS = [TOOL_ORIGIN];

const PATHS: Record<ToolId, string> = {
  mise: "/embed/mise",
  zest: "/embed/zest",
  scale: "/embed/scale",
};

interface Props {
  tool: ToolId;
  theme: "dark" | "light";
  projectName: string | null;
}

export default function ToolPanel({ tool, theme, projectName }: Props) {
  const params = new URLSearchParams({ theme, host: "desktop" });
  if (projectName) params.set("project", projectName);

  return (
    <aside className="nr-panel" aria-label={`${tool} panel`}>
      <iframe
        key={tool}
        title={tool}
        src={`${TOOL_ORIGIN}${PATHS[tool]}?${params.toString()}`}
        sandbox="allow-scripts allow-same-origin allow-forms"
      />
    </aside>
  );
}
