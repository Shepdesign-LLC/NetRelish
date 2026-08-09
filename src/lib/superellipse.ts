/**
 * Superellipse path generator.
 *
 * Mirrors the shape math already used across the NetRelish brand system
 * (JS in the web tools, PHP server-side). Keeping the desktop chrome on the
 * same curve is what stops the app from looking like a generic Tauri shell
 * with border-radius applied.
 *
 * |x/a|^n + |y/b|^n = 1
 *   n = 2   -> ellipse
 *   n = 4   -> the squircle NetRelish uses
 *   n -> inf -> rectangle
 */
export function superellipsePath(size: number, n = 4, steps = 64): string {
  const a = size / 2;
  const b = size / 2;
  const exp = 2 / n;
  const points: string[] = [];

  for (let i = 0; i <= steps; i++) {
    const t = (i / steps) * Math.PI * 2;
    const cos = Math.cos(t);
    const sin = Math.sin(t);
    const x = a + Math.sign(cos) * a * Math.abs(cos) ** exp;
    const y = b + Math.sign(sin) * b * Math.abs(sin) ** exp;
    points.push(`${i === 0 ? "M" : "L"}${x.toFixed(3)} ${y.toFixed(3)}`);
  }

  return `${points.join("")}Z`;
}

/** Ready-to-use CSS value: `clip-path: <this>`. */
export function superellipseClip(size: number, n = 4): string {
  return `path("${superellipsePath(size, n)}")`;
}
