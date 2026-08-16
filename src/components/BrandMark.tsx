interface Props {
  /** Rendered size in px. The art is drawn to fill a square box. */
  size?: number;
}

/** The eight gear teeth, at 45° intervals about the hub. */
const TEETH = [0, 45, 90, 135, 180, 225, 270, 315];

/** The superellipse tile. Plotted point-by-point in the brand asset — it is
 *  NOT a border-radius, and per CLAUDE.md §9 it is the one signature move
 *  that must never be replaced. Copied verbatim from app-icon.svg. */
const TILE =
  "M100.00,50.00L99.99,63.06L99.95,67.23L99.89,70.26L99.80,72.72L99.69,74.82L99.56,76.68L99.40,78.34L99.22,79.86L99.01,81.26L98.77,82.55L98.51,83.76L98.22,84.89L97.91,85.95L97.57,86.95L97.20,87.89L96.81,88.78L96.39,89.63L95.94,90.43L95.46,91.18L94.94,91.90L94.40,92.58L93.83,93.22L93.22,93.83L92.58,94.40L91.90,94.94L91.18,95.46L90.43,95.94L89.63,96.39L88.78,96.81L87.89,97.20L86.95,97.57L85.95,97.91L84.89,98.22L83.76,98.51L82.55,98.77L81.26,99.01L79.86,99.22L78.34,99.40L76.68,99.56L74.82,99.69L72.72,99.80L70.26,99.89L67.23,99.95L63.06,99.99L50.00,100.00L36.94,99.99L32.77,99.95L29.74,99.89L27.28,99.80L25.18,99.69L23.32,99.56L21.66,99.40L20.14,99.22L18.74,99.01L17.45,98.77L16.24,98.51L15.11,98.22L14.05,97.91L13.05,97.57L12.11,97.20L11.22,96.81L10.37,96.39L9.57,95.94L8.82,95.46L8.10,94.94L7.42,94.40L6.78,93.83L6.17,93.22L5.60,92.58L5.06,91.90L4.54,91.18L4.06,90.43L3.61,89.63L3.19,88.78L2.80,87.89L2.43,86.95L2.09,85.95L1.78,84.89L1.49,83.76L1.23,82.55L0.99,81.26L0.78,79.86L0.60,78.34L0.44,76.68L0.31,74.82L0.20,72.72L0.11,70.26L0.05,67.23L0.01,63.06L0.00,50.00L0.01,36.94L0.05,32.77L0.11,29.74L0.20,27.28L0.31,25.18L0.44,23.32L0.60,21.66L0.78,20.14L0.99,18.74L1.23,17.45L1.49,16.24L1.78,15.11L2.09,14.05L2.43,13.05L2.80,12.11L3.19,11.22L3.61,10.37L4.06,9.57L4.54,8.82L5.06,8.10L5.60,7.42L6.17,6.78L6.78,6.17L7.42,5.60L8.10,5.06L8.82,4.54L9.57,4.06L10.37,3.61L11.22,3.19L12.11,2.80L13.05,2.43L14.05,2.09L15.11,1.78L16.24,1.49L17.45,1.23L18.74,0.99L20.14,0.78L21.66,0.60L23.32,0.44L25.18,0.31L27.28,0.20L29.74,0.11L32.77,0.05L36.94,0.01L50.00,0.00L63.06,0.01L67.23,0.05L70.26,0.11L72.72,0.20L74.82,0.31L76.68,0.44L78.34,0.60L79.86,0.78L81.26,0.99L82.55,1.23L83.76,1.49L84.89,1.78L85.95,2.09L86.95,2.43L87.89,2.80L88.78,3.19L89.63,3.61L90.43,4.06L91.18,4.54L91.90,5.06L92.58,5.60L93.22,6.17L93.83,6.78L94.40,7.42L94.94,8.10L95.46,8.82L95.94,9.57L96.39,10.37L96.81,11.22L97.20,12.11L97.57,13.05L97.91,14.05L98.22,15.11L98.51,16.24L98.77,17.45L99.01,18.74L99.22,20.14L99.40,21.66L99.56,23.32L99.69,25.18L99.80,27.28L99.89,29.74L99.95,32.77L99.99,36.94L100.00,50.00Z";

/** The relish pour. Drawn twice — once offset as its own shadow, once lit. */
const GOOP =
  "M15 42 C13 20, 30 7, 50 7 C70 7, 87 20, 85 42 C85 47, 80 49, 76 46 C74 44, 75 46, 74.5 52 C74 60, 65 60, 65 52 C65 47, 66 45, 63 43 C59 41, 57 44, 55 46 C53 49, 47 50, 46 45 C45.5 42, 47 41, 44 40.5 C40 40, 39 42, 38 44 C37 47, 37 49, 36.5 55 C36 63, 27 63, 27 55 C27 49, 28 45, 25 44 C21 43, 17 46, 15 42 Z";

/**
 * The NetRelish app mark: relish poured over a steel gear, on the
 * superellipse tile.
 *
 * Vector-for-vector the brand asset at
 * `NetRelish Brand/Brand Assets/icon/app-icon.svg`, tile included. The
 * handoff calls for it at 36px in the titlebar.
 *
 * Colours are the asset's exact values restated in OKLCH per §9 — not the
 * `--nr-` ramp. The steel has no token, and the pour tokens are near but
 * not equal to the goop gradient. The logo is the logo; it does not
 * re-tint with the system.
 */
export default function BrandMark({ size = 36 }: Props) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 100 100"
      fill="none"
      aria-hidden="true"
      focusable="false"
    >
      <defs>
        <linearGradient id="nr-mark-tile" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="oklch(0.273 0.048 132.1)" />
          <stop offset="1" stopColor="oklch(0.173 0.026 126.6)" />
        </linearGradient>
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

      {/* The superellipse. Never a border-radius. */}
      <path d={TILE} fill="url(#nr-mark-tile)" />

      <g transform="translate(13 13) scale(0.74)">
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
        <path transform="translate(0 3)" opacity="0.2" fill="oklch(0 0 0)" d={GOOP} />
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
      </g>
    </svg>
  );
}
