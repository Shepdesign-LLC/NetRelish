interface Props {
  /** 1..6 — picks the `--nr-jar-N` hue the glass is tinted from. */
  hue: number;
  /** The jar's initial, set into the glass. Omit for an empty jar. */
  initial?: string;
  /** Rendered width in px; height follows the 36:44 aspect. */
  width?: number;
  /** Ring the jar in Relish — used for the active jar on the shelf. */
  glowing?: boolean;
  /** Draw only a dashed silhouette — the "new jar" slot on the shelf. */
  outline?: boolean;
}

/** The jar's body. Shared by the filled and outline forms so the dashed
 *  placeholder is the same shape as a real jar, not a rounded box. */
const BODY =
  "M10 8 H26 V11 C30.5 12.8 33 16 33 20 V36 A7 7 0 0 1 26 43 H10 " +
  "A7 7 0 0 1 3 36 V20 C3 16 5.5 12.8 10 11 Z";

/**
 * A jar, drawn as a mason jar.
 *
 * Lifted from the Aero Relish mocks (`App Redesign - Jar.dc.html`), which
 * draw it on a 36×44 grid: a steel lid, a shouldered glass body, one white
 * gloss streak down the left, and the jar's initial set into the glass.
 *
 * The mock hard-codes a green body because its example jar is green. Here
 * the glass is mixed from the jar's own `--nr-jar-N`, the same `color-mix`
 * recipe the sidebar orbs use — so a Tomato Jam jar reads as red glass.
 *
 * Gradient ids are suffixed per hue: several jars render at once on the
 * shelf, and duplicate ids would make them all share the first jar's fill.
 */
export default function MasonJar({
  hue,
  initial,
  width = 46,
  glowing = false,
  outline = false,
}: Props) {
  const body = `nr-jar-body-${hue}`;
  const lid = `nr-jar-lid-${hue}`;
  const tint = `var(--nr-jar-${hue})`;

  if (outline) {
    return (
      <svg
        width={width}
        height={Math.round((width * 44) / 36)}
        viewBox="0 0 36 44"
        fill="none"
        aria-hidden="true"
        focusable="false"
        style={{ flexShrink: 0 }}
      >
        <rect
          x="8.5"
          y="1"
          width="19"
          height="7"
          rx="3"
          fill="none"
          stroke="currentColor"
          strokeWidth="1.5"
          strokeDasharray="3 2.5"
        />
        <path
          d={BODY}
          fill="none"
          stroke="currentColor"
          strokeWidth="1.5"
          strokeDasharray="3 2.5"
        />
      </svg>
    );
  }

  return (
    <svg
      width={width}
      height={Math.round((width * 44) / 36)}
      viewBox="0 0 36 44"
      fill="none"
      aria-hidden="true"
      focusable="false"
      style={{
        flexShrink: 0,
        filter: glowing
          ? "drop-shadow(0 2px 5px oklch(0.176 0.036 133.5 / 0.4)) drop-shadow(0 0 6px oklch(0.834 0.224 130.9 / 0.75))"
          : "drop-shadow(0 5px 10px oklch(0.176 0.036 133.5 / 0.45))",
      }}
    >
      <defs>
        <linearGradient id={body} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor={`color-mix(in oklab, ${tint} 22%, white)`} />
          <stop offset="1" stopColor={`color-mix(in oklab, ${tint} 88%, black)`} />
        </linearGradient>
        <linearGradient id={lid} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="oklch(0.993 0.004 106.4)" />
          <stop offset="1" stopColor="oklch(0.774 0.030 118.6)" />
        </linearGradient>
      </defs>

      <rect x="8.5" y="1" width="19" height="7" rx="3" fill={`url(#${lid})`} />
      <path
        d="M10 8 H26 V11 C30.5 12.8 33 16 33 20 V36 A7 7 0 0 1 26 43 H10 A7 7 0 0 1 3 36 V20 C3 16 5.5 12.8 10 11 Z"
        fill={`url(#${body})`}
      />
      {/* The one gloss streak — what makes it read as glass, not a bottle. */}
      <path
        d="M8.5 16.5 C6.6 18 5.6 19.8 5.6 22 V34.5"
        stroke="oklch(1 0 0 / 0.55)"
        strokeWidth="2.6"
        fill="none"
        strokeLinecap="round"
      />
      {initial && (
        <text
          x="18"
          y="32"
          textAnchor="middle"
          fontFamily="Bricolage Grotesque, sans-serif"
          fontWeight="800"
          fontSize="14"
          fill={`color-mix(in oklab, ${tint} 42%, black)`}
        >
          {initial}
        </text>
      )}
    </svg>
  );
}
