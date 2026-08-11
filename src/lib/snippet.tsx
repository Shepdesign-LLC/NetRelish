import { MARK_END, MARK_START } from "./db";

/**
 * Split a snippet on the FTS5 highlight delimiters into safe React nodes —
 * page text never becomes markup. Shared by the palette and Brine rows.
 */
export function renderSnippet(text: string): React.ReactNode[] {
  const nodes: React.ReactNode[] = [];
  let rest = text;
  let key = 0;
  while (true) {
    const start = rest.indexOf(MARK_START);
    if (start === -1) break;
    const end = rest.indexOf(MARK_END, start);
    if (end === -1) break;
    if (start > 0) nodes.push(rest.slice(0, start));
    nodes.push(<mark key={key++}>{rest.slice(start + 1, end)}</mark>);
    rest = rest.slice(end + 1);
  }
  nodes.push(rest);
  return nodes;
}
