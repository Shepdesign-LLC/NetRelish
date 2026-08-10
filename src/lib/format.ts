/** Presentation helpers shared by the list surfaces. */

/** "https://www.example.com/x" → "example.com"; never throws. */
export function domainOf(url: string | null): string {
  if (!url) return "";
  try {
    return new URL(url).hostname.replace(/^www\./, "");
  } catch {
    return "";
  }
}

/** Address-bar semantics: URL if it reads like one, else a web search. */
export function normalizeUrl(input: string): string {
  const trimmed = input.trim();
  if (!trimmed) return "";
  if (/^https?:\/\//i.test(trimmed)) return trimmed;
  if (/^[\w-]+(\.[\w-]+)+(\/|$)/.test(trimmed)) return `https://${trimmed}`;
  return `https://duckduckgo.com/?q=${encodeURIComponent(trimmed)}`;
}

/** Deny-list file → lowercase patterns; mirrors denylist.rs exactly. */
export function parseDenyList(contents: string): string[] {
  return contents
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l.length > 0 && !l.startsWith("#"))
    .map((l) => l.toLowerCase());
}

/** True when normalizeUrl would treat the input as an address, not a search. */
export function looksLikeUrl(input: string): boolean {
  const trimmed = input.trim();
  return (
    /^https?:\/\//i.test(trimmed) || /^[\w-]+(\.[\w-]+)+(\/|$)/.test(trimmed)
  );
}
