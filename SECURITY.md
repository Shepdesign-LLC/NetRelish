# Security

## Reporting a vulnerability

Please report security problems privately, not in a public issue or pull request.

1. Open the repository's **Security** tab: <https://github.com/Shepdesign-LLC/NetRelish/security>
2. Choose **Report a vulnerability**. That opens a private advisory only you and the
   maintainers can see.
3. Say what you found, how to reproduce it, and which version or commit you tested.

If you don't see a **Report a vulnerability** button, open a regular issue that says only
that you have a security report and would like a private way to send it. Leave the details
out of that issue.

You are welcome to include a suggested fix. Please give us a chance to ship a fix before
you publish details.

## What is in scope

- **The Mac app**: everything under `Sources/` and `Resources/`, including page capture,
  Seal, the Pantry database, jar profiles (cookies and sessions that cross jars), the Share
  extension, and anything that makes the app send browsing data off the device.
- **The Zest tools**: the web tools under `zest/` (the studio, ZestMail, Zest MD,
  ZestImage) and the small server function ZestMail can call.
- **The release pipeline**: the workflows under `.github/workflows/`, the scripts they run,
  and how the signed, notarized download is built and published.

## What is not in scope

- Problems in third-party software NetRelish depends on, unless NetRelish uses it in a way
  that creates the problem. Please report those to the project concerned. If the issue
  affects NetRelish users, tell us as well.
- The marketing site, which lives in a separate repository.
