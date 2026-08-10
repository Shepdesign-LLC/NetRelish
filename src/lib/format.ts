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
