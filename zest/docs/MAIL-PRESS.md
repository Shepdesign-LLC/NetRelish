---
title: Mail Press — reference
author: Ryan / Shepdesign LLC
updated: 2026-09-18
version: 3
---

# Mail Press

A single-file email builder and generator. Design in blocks, re-skin per brand, drop in the right merge tags for your platform, and export HTML that survives Outlook. Everything runs in the browser; nothing leaves the machine unless you use the Claude panel.

Two ways to work, one pipeline underneath:

- **Build** — drag blocks onto a canvas, click text to edit it, pick a brand. The builder writes table-based HTML for you.
- **Source** — paste any HTML (yours, or what a model produced from your design). The compiler inlines the CSS and wraps it for email clients.

Both feed the same compiler and linter, and both export the same way.

---

## 1. Thirty-second tour

1. Open `mail-press.html`. You're in **Build** mode.
2. Click **Newsletter** under Templates. Seven blocks appear.
3. Click the headline on the canvas and type. It's live.
4. **Brand** tab → pick or create a brand. The whole email re-skins.
5. **Message** tab → subject and preheader.
6. Top bar: **Desktop / Mobile / Outlook** to preview. **Lint** tab tells you what clients will complain about and why.
7. **Export → Copy email HTML**. Paste into Bento's HTML/CSS editor.

---

## 2. Build mode

### 2.1 The canvas

The centre pane is the email at your chosen width (Message tab → Width). Each block is selectable; the selected block gets a blue outline, a name tag, and four tools: move up, move down, duplicate, delete.

| Action | How |
|---|---|
| Add a block | Drag from the left panel onto the canvas, or click it to append |
| Reorder | Drag a block above or below another; a blue line shows where it lands |
| Select | Click the block. Click empty canvas or press Esc to deselect |
| Delete | Delete key with a block selected, or the trash tool. An Undo toast follows |
| Undo | ⌘Z, or the undo arrow in the top bar. Fifty steps |
| Edit text | Click any text and type. See 2.3 |

### 2.2 Blocks

Thirteen. All table-based, all stack on mobile, all take their colors from the brand unless you override them.

| Block | What it's for |
|---|---|
| **Logo header** | Brand logo (or company name if no logo), optional tagline, optional "View in browser" line |
| **Hero** | Eyebrow, headline, lede, optional image, CTA. Dark panel by default |
| **Text** | Heading and body. Body takes `**bold**`, `*italic*`, `[link](url)`; blank line = new paragraph |
| **Image** | Full width or fixed width, optional link, alt text |
| **Button** | Bulletproof CTA; renders as a table cell so Outlook draws the background |
| **Two columns** | 50/50, 40/60 or 60/40, each side optional image plus text |
| **Feature grid** | Three cards |
| **Product card** | Image, title, text, price line, button |
| **Quote** | Pull quote with attribution |
| **Divider** | One-pixel rule |
| **Spacer** | Vertical room |
| **Social links** | Text links from the brand's social URLs (no icons: icons need hosted images) |
| **Footer** | Company, address, note, and the platform's unsubscribe link — see §4 |

Every block has a **Padding** slider and a **Background** color; most have **Align**.

### 2.3 Editing text on the canvas

Click any headline, paragraph, button label, card or footer note and type.

- Single-line fields (headlines, labels): **Enter** commits, **Esc** cancels the focus.
- Rich fields (body text, columns, cards, footer note): **⌘B** bold, **⌘I** italic, **⌘K** link. Enter makes a new paragraph.
- Paste is plain-text only, so nothing brings Word styling with it.
- What you type on the canvas appears in the inspector field, and the other way round.

### 2.4 The inspector (right panel)

| Tab | Holds |
|---|---|
| **Block** | Fields for the selected block, the **Insert tag** menu, and **Save as module** |
| **Brand** | Brand switcher and every brand setting (§3) |
| **Message** | Subject, preheader, width, outer background, fallback fonts, dark-mode metadata, wrapper and attribute-mirroring toggles |
| **Lint** | Compatibility flags with explanations, plus stats |
| **Claude** | Optional model assistance (§7) |

**Color fields** are a dropdown of brand tokens (Brand primary, Brand text, Brand dark, …) plus **Custom…**, which enables the color picker beside it. Leave colors on brand tokens if you want the design to re-skin when you switch brand.

### 2.5 Templates

Seven starting points: Newsletter, Product launch, Announcement, Welcome, Event invite, Transactional, Plain note. Loading one replaces the canvas (Undo works). They're built from the same blocks, so everything is editable afterwards.

### 2.6 Modules

Select a block, click **Save as module**, name it. It appears under **My modules** on the left with its content and colors, ready to drag into any design. Use it for a house footer, a branded hero, a legal block. Remove with the "remove" link on the card.

### 2.7 Saving

- **Save** (top bar) stores the design in this browser, under Saved designs on the left. Open with ↗, delete with ×.
- **Export → Download design (.json)** gives you a portable file that includes the brand. **Import design** loads one. This is how a design moves between machines or people.
- The current canvas autosaves as a draft and comes back when you reopen the page.

---

## 3. Brands

One brand per site. In Bento terms, one brand per Bento site.

| Section | Fields |
|---|---|
| Identity | Name, **Platform** (Bento / plain URLs / custom), **Bento site**, logo URL, logo width, company, address, website |
| Colors | Primary, text, muted text, dark panel, sheet, page, lines |
| Type | Font stack, corner radius |
| Links | Unsubscribe URL, preferences URL, Instagram, LinkedIn, X, Facebook, YouTube |
| Custom platform tags | Only used when Platform is "custom" |

**New brand** starts from defaults. **Duplicate** copies the current one — the fast way to spin up a sister brand. Brands persist in the browser and ride inside exported `.json` designs.

Switching brand in the dropdown re-renders the canvas immediately. If a block's color is set to a brand token it follows; if you set a custom hex it stays put. That's the rule for everything: tokens follow the brand, literals don't.

---

## 4. Merge tags and Bento

**Platform** on the Brand tab decides which tags the tool uses. Set to **Bento**, these are the exact Liquid tags from Bento's guide:

| Purpose | Tag |
|---|---|
| First name with fallback | `{{ visitor.first_name \| default: "there" }}` |
| Last name | `{{ visitor.last_name }}` |
| Email | `{{ visitor.email }}` |
| Subject line | `{{ subject }}` |
| Unsubscribe URL | `{{ visitor.unsubscribe_url }}` |
| View in browser | `{{ browser_url }}` |
| Snooze | `{{ visitor.snooze_url }}` |

Where they go automatically:

- **Footer** → Unsubscribe uses the platform tag. Toggles add Snooze, View in browser, and a Preferences link (Preferences uses the brand's real URL; Bento has no tag for it).
- **Logo header** → the "View in browser" toggle uses `{{ browser_url }}`.
- **Insert tag** menu (top of the Block tab) → drops any tag into the field you last clicked. If you haven't clicked a field, it appends to the block's main text.
- Any link field accepts a tag as the URL. So does ⌘K on the canvas.

How tags display:

| Where | What you see |
|---|---|
| Canvas | The raw tag, e.g. `{{ visitor.first_name \| default: "there" }}` — so you can see and edit it |
| Desktop / Mobile / Outlook preview | Sample values — "Jamie", `example.com/unsubscribe` — so the design reads like a real send |
| Export | The raw tags, untouched, for Bento to render |

Set Platform to **plain URLs** and the footer uses the brand's real unsubscribe address instead; the tag menu goes empty. **Custom** lets you type your own first-name, unsubscribe and view-in-browser tags for another platform.

### 4.1 Into Bento

1. Build → choose the brand for that site → Export → **Copy email HTML**.
2. In Bento, open the email, switch the editor to **HTML/CSS**, paste.
3. Bento enforces at least one unsubscribe link; the footer block provides it.
4. Send a test to yourself. The linter is not an inbox.

---

## 5. Source mode

For HTML you didn't build here — your own, or a model's output from your design.

Paste into the left pane. The compiler:

1. Pulls every `<style>` block out and parses it.
2. Inlines plain rules onto elements **by specificity, in source order**, `!important` respected, existing inline styles winning last. That's what browsers do, so the result matches what the designer saw.
3. Keeps `@media` and `:hover` rules in `<head>` for clients that honour them.
4. Mirrors `bgcolor`, `width`, `align`, `valign` as attributes and sets `role="presentation"` on tables — what Outlook actually reads.
5. Appends a fallback stack to any web font.
6. Wraps everything in a 100% outer table plus a centred container with an MSO conditional, adds the XHTML doctype, resets, dark-mode metadata and the hidden preheader.
7. Strips scripts, forms, media and SVG (and tells you).

**Open in Source** from the Export menu hands a compiled Build-mode email to this pane for hand edits. The builder keeps your blocks.

---

## 6. Previews, lint, export

**Views:** Canvas (build mode only), Desktop at 600px, Mobile at 375px, **Outlook** — a simulation that strips what Word's rendering engine drops (border-radius, box-shadow, background images, flex, web fonts) so you see the real degradation before a Windows user does.

**Lint** flags with an explanation each, for example:

- Flexbox, grid, position, float, gap → blocking; Outlook and Gmail don't do them
- `rem` / viewport units → Outlook ignores them
- Web fonts → fallback appended; Gmail and Outlook use it
- Images without `alt` or `width` → what blocked-image readers see, and Outlook's retina sizing
- No preheader, no links, no unsubscribe text
- Size: warning past 80 KB, blocking past ~102 KB, where Gmail clips

The pill in the top bar is the summary: clean, *n* to review, or *n* blocking.

**Export menu:**

| Item | Gives you |
|---|---|
| Copy email HTML (⌘S) | The compiled document, tags intact |
| Download .html | Same, as a file named from the subject |
| Copy plain-text version | Text twin: headings uppercased, links as `text (url)`, lists as dashes |
| Open in Source | Compiled HTML into the Source pane |
| Download / Import design (.json) | Portable design with brand |

---

## 7. Claude panel (optional)

Bring your own key, or route through the server proxy in the hosted version. The model never bypasses the pipeline: output lands in Source and gets compiled and linted like anything you paste.

- **Draft from brief** — sends your brief plus the current brand (colors, fonts, footer, platform tags) and a system prompt that already knows the email rules.
- **Fix flagged issues** — sends the current HTML and the lint flags, asks for a rewrite that resolves them while keeping the design.

**Routes**

| Route | When | Where the key lives |
|---|---|---|
| Direct | Personal use over http(s) | Your browser only |
| Server proxy | Hosted on Vercel (`mailpress-vercel.zip`) | Vercel environment variable |
| Sandbox | claude.ai artifact preview, auto-detected | The viewer's |

Direct does not work from a `file://` page — browsers block cross-origin calls from local files with a CORS error. Serve it (`npx serve .`) or use the hosted build. The note under the key field tells you which route is active and why.

---

## 8. Hosting

`mailpress-vercel.zip` is the same app plus `api/claude.js`, a serverless function that keeps the key on the server.

```bash
unzip mailpress-vercel.zip && cd mailpress
npx vercel --prod
```

Vercel → Project → Settings → Environment Variables:

- `ANTHROPIC_API_KEY` — your key
- `MAILPRESS_TOKEN` — any long random string; enter the same value under Claude → Proxy token so strangers can't spend your credits through the endpoint

Leave the API key field empty and Route on Auto; hosted pages pick the proxy.

---

## 9. What it deliberately doesn't do

- **Convert a flexbox or grid layout into tables automatically.** That's a design decision, not a transform. The linter flags it; the Claude panel can propose a table rewrite you review.
- **Host images.** Image fields take URLs. Your S3 bucket is the right home; an upload button that writes there is the next feature.
- **Send.** Bento sends. A test-send button via Resend is on the list.
- **Use anyone else's editor code.** The builder is original. Nothing depends on a third-party auth server.

---

## 10. Keyboard

| Keys | Does |
|---|---|
| ⌘S | Copy email HTML |
| ⌘Z | Undo (canvas) |
| Delete / Backspace | Remove selected block |
| Esc | Deselect, or leave a text field |
| Enter | Commit a single-line field |
| ⌘B / ⌘I / ⌘K | Bold / italic / link in rich text |
| Tab (Source pane) | Two spaces |

---

## 11. Files

| File | What |
|---|---|
| `mail-press.html` | The app. Open it in a browser |
| `mailpress-vercel.zip` | Hosted build with the Claude proxy |
| `PRESS-TOOLS.md` | Tenets, MD Press internals, roadmap, the path to macOS apps |
