# Checksums for vendored files

Third-party files that ship inside the app are recorded here with a SHA-256, and CI
fails if a file no longer matches its record (`.github/workflows/ci.yml`, job
"Generated files match their sources").

| File | What it is | Upstream | Version | License |
|---|---|---|---|---|
| `Resources/Extraction/defuddle.js` | Defuddle, the page-text extractor injected at capture | <https://github.com/kepano/defuddle> | **Not recorded.** See below. | MIT, `Resources/Extraction/defuddle-LICENSE.txt` |

## Why the checksum lives here and not next to the file

`project.yml` copies the whole `Resources/` folder into the app bundle. A checksum or
README placed there would ship inside NetRelish.app and change the generated Xcode
project. `scripts/` is not bundled.

## What is known about defuddle.js

- Added on 2026-09-23 in commit `71574ff` and not changed since.
- 338,304 bytes, one line, a browser (UMD) build that defines `Defuddle`.
- The file has no version banner, and nothing in the repository says which upstream
  release or build file it is. The version is unknown, not guessed.

To close that gap, someone needs to find the published Defuddle release whose browser
build has this exact SHA-256, then write the version and the file's path inside that
release into the table above. If no release matches byte for byte, vendor a named
release instead and record it here.

## Checking

From the repository root:

```
shasum -a 256 -c scripts/checksums/defuddle.js.sha256
```

## Updating the vendored file

1. Replace `Resources/Extraction/defuddle.js` with the new build, and the license file
   if it changed.
2. Record the upstream version in the table above.
3. Rewrite the checksum: `shasum -a 256 Resources/Extraction/defuddle.js > scripts/checksums/defuddle.js.sha256`
4. Put all three in the same pull request, so the reviewer sees a new file, a named
   version and a new checksum together.
