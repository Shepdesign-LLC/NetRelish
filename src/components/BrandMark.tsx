interface Props {
  /** Rendered size in px. The art is drawn to fill a square box. */
  size?: number;
}

/** The eight gear teeth, at 45° intervals about the hub. */
const TEETH = [0, 45, 90, 135, 180, 225, 270, 315];

/** The relish pour. Drawn twice — once offset as its own shadow, once lit. */
const GOOP =
  "M15 42 C13 20, 30 7, 50 7 C70 7, 87 20, 85 42 C85 47, 80 49, 76 46 " +
  "C74 44, 75 46, 74.5 52 C74 60, 65 60, 65 52 C65 47, 66 45, 63 43 " +
  "C59 41, 57 44, 55 46 C53 49, 47 50, 46 45 C45.5 42, 47 41, 44 40.5 " +
  "C40 40, 39 42, 38 44 C37 47, 37 49, 36.5 55 C36 63, 27 63, 27 55 " +
  "C27 49, 28 45, 25 44 C21 43, 17 46, 15 42 Z";

/**
 * The NetRelish mark: relish poured over a steel gear.
 *
 * Vector-for-vector the brand asset at
 * `NetRelish Brand/Brand Assets/icon/app-icon.svg`, with two changes:
 *
 *  - No tile behind it. The app icon needs its dark squircle to sit in a
 *    Dock; in the titlebar the mark sits on glass, and the tile would both
 *    look pasted on and block the Aurora from showing through.
 *  - Colours restated in OKLCH per §9. These are the asset's exact values
 *    converted, not the `--nr-` ramp — the steel has no token, and the pour
 *    tokens are near but not equal to the goop gradient. The logo is the
 *    logo; it does not re-tint with the system.
 */
export default function BrandMark({ size = 22 }: Props) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="6 6 88 88"
      fill="none"
      aria-hidden="true"
      focusable="false"
    >
      <defs>
        <linearGradient id="nr-mark-steel" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="oklch(0.861 0.013 251.6)" />
          <stop offset="1" stopColor="oklch(0.640 0.021 255.6)" />
        </linearGradient>
        <radialGradient id="nr-mark-hole" cx="0.5" cy="0.38" r="0.7">
          <stop offset="0" stopColor="oklch(0.369 0.020 257.3)" />
          <stop offset="1" stopColor="oklch(0.492 0.021 253.5)" />
        </radialGradient>
        <linearGradient id="nr-mark-goop" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="oklch(0.878 0.220 128.9)" />
          <stop offset="1" stopColor="oklch(0.698 0.204 136.0)" />
        </linearGradient>
        <linearGradient id="nr-mark-gloss" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="oklch(1 0 0)" stopOpacity="0.6" />
          <stop offset="1" stopColor="oklch(1 0 0)" stopOpacity="0" />
        </linearGradient>
      </defs>

      {/* The gear's dark underside, offset down — this is what gives the
          steel its thickness. */}
      <g transform="translate(0 4.5)" fill="oklch(0.465 0.021 256.4)">
        {TEETH.map((a) => (
          <rect
            key={a}
            x="43.5"
            y="12"
            width="13"
            height="13"
            rx="4"
            transform={a ? `rotate(${a} 50 50)` : undefined}
          />
        ))}
        <circle cx="50" cy="50" r="30" />
      </g>

      <g fill="url(#nr-mark-steel)">
        {TEETH.map((a) => (
          <rect
            key={a}
            x="43.5"
            y="12"
            width="13"
            height="13"
            rx="4"
            transform={a ? `rotate(${a} 50 50)` : undefined}
          />
        ))}
        <circle cx="50" cy="50" r="30" />
      </g>

      <circle cx="50" cy="50" r="11" fill="url(#nr-mark-hole)" />

      {/* The pour, and the shadow it casts on the steel. */}
      <path
        transform="translate(0 3)"
        opacity="0.2"
        fill="oklch(0 0 0)"
        d={GOOP}
      />
      <path fill="url(#nr-mark-goop)" d={GOOP} />

      <ellipse
        cx="37"
        cy="17"
        rx="15"
        ry="6"
        transform="rotate(-14 37 17)"
        fill="url(#nr-mark-gloss)"
      />

      {/* Specks in the relish, and the drip running off the rim. */}
      <g fill="oklch(0.589 0.165 134.7)" opacity="0.85">
        <circle cx="31" cy="26" r="1.7" />
        <circle cx="52" cy="16" r="1.7" />
        <circle cx="67" cy="27" r="1.7" />
      </g>
      <g fill="oklch(0.936 0.137 122.8)" opacity="0.9">
        <circle cx="45" cy="32" r="1.7" />
        <circle cx="60" cy="35" r="1.4" />
      </g>
      <ellipse cx="31.5" cy="71" rx="2.6" ry="3.4" fill="oklch(0.698 0.204 136.0)" />
    </svg>
  );
}
