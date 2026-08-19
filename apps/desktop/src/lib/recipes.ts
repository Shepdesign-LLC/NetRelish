/**
 * Recipe steps: the readable, hand-editable JSON a recipe is made of
 * (§11 week 7). Recorded from real work, or edited directly.
 */

export type RecipeStep =
  | { kind: "open"; url: string }
  | { kind: "split"; left: string; right: string }
  | { kind: "task"; text: string }
  | { kind: "note"; text: string }
  | { kind: "collect" }
  | { kind: "seal" };

const KINDS = new Set(["open", "split", "task", "note", "collect", "seal"]);

/** Parse steps JSON defensively — it may have been hand-edited. */
export function parseSteps(json: string): RecipeStep[] | string {
  let raw: unknown;
  try {
    raw = JSON.parse(json);
  } catch (e) {
    return `not valid JSON: ${String(e)}`;
  }
  if (!Array.isArray(raw)) return "steps must be a JSON array";
  for (const [i, step] of raw.entries()) {
    if (typeof step !== "object" || step === null || Array.isArray(step))
      return `step ${i + 1} must be an object`;
    const s = step as Record<string, unknown>;
    if (typeof s.kind !== "string" || !KINDS.has(s.kind))
      return `step ${i + 1}: unknown kind "${String(s.kind)}"`;
    if (s.kind === "open" && typeof s.url !== "string")
      return `step ${i + 1}: open needs a "url"`;
    if (s.kind === "split" && (typeof s.left !== "string" || typeof s.right !== "string"))
      return `step ${i + 1}: split needs "left" and "right"`;
    if ((s.kind === "task" || s.kind === "note") && typeof s.text !== "string")
      return `step ${i + 1}: ${s.kind} needs a "text"`;
  }
  return raw as RecipeStep[];
}

export interface InterpolationContext {
  jar: string;
  url: string;
}

/** {{date}}, {{jar}}, {{url}} — filled at run time, never at save time. */
export function interpolate(text: string, ctx: InterpolationContext): string {
  const date = new Date().toLocaleDateString("en-CA"); // YYYY-MM-DD
  return text
    .replaceAll("{{date}}", date)
    .replaceAll("{{jar}}", ctx.jar)
    .replaceAll("{{url}}", ctx.url);
}

/** One line the runner shows for a step. */
export function stepLabel(step: RecipeStep): string {
  switch (step.kind) {
    case "open":
      return `Open ${step.url}`;
    case "split":
      return `Split: ${step.left} ⇄ ${step.right}`;
    case "task":
      return step.text;
    case "note":
      return `Note: ${step.text.split("\n")[0]}`;
    case "collect":
      return "Jar the current page";
    case "seal":
      return "Seal the tabs this recipe opened";
  }
}
