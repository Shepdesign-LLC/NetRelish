# Building the NetRelish model in System Designer — complete, in order

This is the whole job, start to finish. Follow it top to bottom and the export at the
end is what Prompt 3 (`docs/KICKOFF.md`) generates the Pantry from. It replaces the older
`NetRelish_SystemDesigner_Workflow.md`, which described the SwiftData plan.

```
Systems → Types (5) → Schemas (7) → Models (7) → Behaviors (7) → Components (4) → Export → /design/NetRelish.json
```

**What it produces:** one root (`NetRelish`), six things it owns (`Item`, `Jar`, `Recipe`,
`Step`, `Label`, `Batch`), five enums, seven method/event bodies, and four seed records.
`Brine` is not a thing in the model — it is the Items whose `jar` is empty. `Pickle` is not
in the model yet — it is v1.2 and Direct-build only; it gets added when that phase comes.

---

## The rules (each one has cost time)

| Rule | Why it matters |
|---|---|
| Every editor is **JSON**, except Behaviors, which are **JavaScript**. | Wrong language = an error on line 1. |
| **Types** use `name`. **Schemas** and **Models** use `_name`. | "property 'name' is missing" means you're in the wrong tab. |
| Schema values are **roles**, not types: `property`, `link`, `collection`, `method`, `event`. | `"title": "String"` is rejected. Types go in the Models tab. |
| Every JSON block below is **complete**. Select all → paste → put the editor's own `_id` back on line 2 → ✓. | A fragment is invalid JSON. The `_id` is generated; keep it. |
| Names are unique. **Create once, then edit from the right-hand list.** | A second Create with the same name fails. |
| ✓ saves. ↺ reverts. **✕ on a card DELETES it.** It does not close it. | This is how `Item`, `Recipe`, and `Step` were lost last time. |
| Behaviors are **not** created from the Behaviors tab **+**. That button only makes `start` / `stop` / `error`. Method bodies open by clicking the **blue method name on the model's box** in the Models tab. | |
| One behavior per method. If Create bounces, it already exists — click into it. | |
| There are **two `seal`s**: `NetRelish.seal(item)` takes a parameter, `Item.seal()` takes none. Different bodies. Check the signature line before pasting. | |
| Never declare `id`, `init`, `destroy`, `error`, or `require`. They come from `_Component`. | |
| Do the steps **in order**. Models need Types. Behaviors need Models. Components need each other. | |

---

## 0 · Systems tab

You already have this. Confirm: name `NetRelish`, version `0.2.0`, description
`Savor the web. Get more done.` Nothing else to do here.

---

## 1 · Types tab — five enums ✅ (already done in your export)

These are complete and correct in your current file. Listed so the doc is whole; skip if
they exist. For each: **+** → name → tick **Enumeration** → Create → select all → paste →
restore `_id` → ✓.

```json
{ "_id": "KEEP-THE-EDITORS-ID", "name": "ItemKind", "description": "What an Item is. The single discriminator.", "type": "string", "value": ["page", "note", "task", "file", "message", "clip"] }
```
```json
{ "_id": "KEEP-THE-EDITORS-ID", "name": "ItemState", "description": "Where an Item is in its life. Seal is the only one-way move.", "type": "string", "value": ["brined", "jarred", "sealed"] }
```
```json
{ "_id": "KEEP-THE-EDITORS-ID", "name": "RecipeTrigger", "description": "What starts a Recipe.", "type": "string", "value": ["manual", "onCapture", "onSeal", "onJarDrop", "scheduled"] }
```
```json
{ "_id": "KEEP-THE-EDITORS-ID", "name": "StepAction", "description": "The atomic operations a Step can perform on an Item.", "type": "string", "value": ["addLabel", "removeLabel", "moveToJar", "seal", "summarize", "extractLinks", "extractTasks", "ocrImage", "exportMarkdown", "exportPDF", "runShortcut", "notify"] }
```
```json
{ "_id": "KEEP-THE-EDITORS-ID", "name": "CaptureSource", "description": "How an Item entered the Pantry.", "type": "string", "value": ["browse", "shareExtension", "clipboard", "drop", "shortcut", "recipe"] }
```

---

## 2 · Schemas tab — seven schemas (six are missing)

`NetRelish` exists. Create the other six, **Item first**, in this order:
Item, Jar, Recipe, Step, Label, Batch. For each: **+** → name → Create → select all →
paste → restore `_id` → ✓.

### Item
```json
{
  "_id": "KEEP-THE-EDITORS-ID",
  "_name": "Item",
  "_inherit": ["_Component"],
  "kind": "property",
  "state": "property",
  "title": "property",
  "url": "property",
  "domain": "property",
  "excerpt": "property",
  "body": "property",
  "snapshotPath": "property",
  "source": "property",
  "meta": "property",
  "createdAt": "property",
  "updatedAt": "property",
  "sealedAt": "property",
  "jar": "link",
  "batch": "link",
  "labels": "collection",
  "seal": "method",
  "onSealed": "event"
}
```

### Jar
```json
{
  "_id": "KEEP-THE-EDITORS-ID",
  "_name": "Jar",
  "_inherit": ["_Component"],
  "name": "property",
  "glyph": "property",
  "tint": "property",
  "sortOrder": "property",
  "isPinned": "property",
  "shelfLifeDays": "property",
  "defaultRecipe": "link",
  "items": "collection",
  "onItemDropped": "event"
}
```

### Recipe
```json
{
  "_id": "KEEP-THE-EDITORS-ID",
  "_name": "Recipe",
  "_inherit": ["_Component"],
  "name": "property",
  "trigger": "property",
  "schedule": "property",
  "isShortcutExposed": "property",
  "lastRunAt": "property",
  "steps": "collection",
  "run": "method",
  "onRunFinished": "event"
}
```

### Step
```json
{
  "_id": "KEEP-THE-EDITORS-ID",
  "_name": "Step",
  "_inherit": ["_Component"],
  "order": "property",
  "action": "property",
  "params": "property",
  "haltOnFail": "property",
  "recipe": "link",
  "execute": "method"
}
```

### Label
```json
{
  "_id": "KEEP-THE-EDITORS-ID",
  "_name": "Label",
  "_inherit": ["_Component"],
  "name": "property",
  "tint": "property",
  "items": "collection"
}
```

### Batch
```json
{
  "_id": "KEEP-THE-EDITORS-ID",
  "_name": "Batch",
  "_inherit": ["_Component"],
  "status": "property",
  "createdAt": "property",
  "finishedAt": "property",
  "recipe": "link",
  "items": "collection",
  "onFinished": "event"
}
```

### NetRelish (already exists — confirm it reads exactly this)
```json
{
  "_id": "KEEP-THE-EDITORS-ID",
  "_name": "NetRelish",
  "_inherit": ["_Component"],
  "tagline": "property",
  "brine": "collection",
  "jars": "collection",
  "recipes": "collection",
  "labels": "collection",
  "activeJar": "link",
  "capture": "method",
  "seal": "method",
  "runRecipe": "method",
  "onCapture": "event",
  "onSeal": "event"
}
```

**Checkpoint:** the Models tab's right-hand list shows seven names — models are generated
from schemas, so that list is the proof. (The Schemas tab itself shows **one schema per
page**; the right-hand list there only names the current page. Step through pages with the
**‹ ›** arrows at the top right. Nothing is missing when you only see one.)

---

## 3 · Models tab — seven models (six are missing)

System Designer creates one model per schema automatically, with every field typed `any`.
Click each model in the right-hand list, select all, paste, restore `_id`, ✓.
Same order: Item, Jar, Recipe, Step, Label, Batch, then re-check NetRelish.

### Item
```json
{
  "_id": "KEEP-THE-EDITORS-ID",
  "_name": "Item",
  "_description": "Everything the user saves. One table. kind is the discriminator.",
  "kind":         { "type": "ItemKind",      "readOnly": false, "mandatory": true,  "default": "page" },
  "state":        { "type": "ItemState",     "readOnly": false, "mandatory": true,  "default": "brined" },
  "title":        { "type": "string",        "readOnly": false, "mandatory": true,  "default": "" },
  "url":          { "type": "string",        "readOnly": false, "mandatory": false, "default": "" },
  "domain":       { "type": "string",        "readOnly": false, "mandatory": false, "default": "" },
  "excerpt":      { "type": "string",        "readOnly": false, "mandatory": false, "default": "" },
  "body":         { "type": "string",        "readOnly": false, "mandatory": false, "default": "" },
  "snapshotPath": { "type": "string",        "readOnly": false, "mandatory": false, "default": "" },
  "source":       { "type": "CaptureSource", "readOnly": true,  "mandatory": true,  "default": "browse" },
  "meta":         { "type": "object",        "readOnly": false, "mandatory": false, "default": {} },
  "createdAt":    { "type": "date",          "readOnly": true,  "mandatory": true,  "default": "1970-01-01T00:00:00.000Z" },
  "updatedAt":    { "type": "date",          "readOnly": false, "mandatory": true,  "default": "1970-01-01T00:00:00.000Z" },
  "sealedAt":     { "type": "date",          "readOnly": false, "mandatory": false, "default": "1970-01-01T00:00:00.000Z" },
  "jar":          { "type": "Jar",           "readOnly": false, "mandatory": false, "default": "" },
  "batch":        { "type": "Batch",         "readOnly": false, "mandatory": false, "default": "" },
  "labels":       { "type": ["Label"],       "readOnly": false, "mandatory": false, "default": [] },
  "seal":         { "params": [], "result": "Item" },
  "onSealed":     { "params": [ { "name": "item", "type": "Item" } ] }
}
```

### Jar
```json
{
  "_id": "KEEP-THE-EDITORS-ID",
  "_name": "Jar",
  "_description": "A project, and a profile. Has a shelf life. Where Brine goes once sorted.",
  "name":          { "type": "string",  "readOnly": false, "mandatory": true,  "default": "" },
  "glyph":         { "type": "string",  "readOnly": false, "mandatory": false, "default": "nr-jar" },
  "tint":          { "type": "string",  "readOnly": false, "mandatory": false, "default": "" },
  "sortOrder":     { "type": "number",  "readOnly": false, "mandatory": false, "default": 0 },
  "isPinned":      { "type": "boolean", "readOnly": false, "mandatory": false, "default": false },
  "shelfLifeDays": { "type": "number",  "readOnly": false, "mandatory": false, "default": 3 },
  "defaultRecipe": { "type": "Recipe",  "readOnly": false, "mandatory": false, "default": "" },
  "items":         { "type": ["Item"],  "readOnly": false, "mandatory": false, "default": [] },
  "onItemDropped": { "params": [ { "name": "item", "type": "Item" } ] }
}
```

### Recipe
```json
{
  "_id": "KEEP-THE-EDITORS-ID",
  "_name": "Recipe",
  "_description": "A repeatable workflow. Ordered Steps, one Trigger. Every Recipe is an App Intent.",
  "name":              { "type": "string",        "readOnly": false, "mandatory": true,  "default": "" },
  "trigger":           { "type": "RecipeTrigger", "readOnly": false, "mandatory": true,  "default": "manual" },
  "schedule":          { "type": "string",        "readOnly": false, "mandatory": false, "default": "" },
  "isShortcutExposed": { "type": "boolean",       "readOnly": false, "mandatory": false, "default": true },
  "lastRunAt":         { "type": "date",          "readOnly": false, "mandatory": false, "default": "1970-01-01T00:00:00.000Z" },
  "steps":             { "type": ["Step"],        "readOnly": false, "mandatory": false, "default": [] },
  "run":               { "params": [ { "name": "items", "type": ["Item"], "mandatory": true } ], "result": "Batch" },
  "onRunFinished":     { "params": [ { "name": "batch", "type": "Batch" } ] }
}
```

### Step
```json
{
  "_id": "KEEP-THE-EDITORS-ID",
  "_name": "Step",
  "_description": "One atomic unit of a Recipe. A function of Item -> Item.",
  "order":      { "type": "number",     "readOnly": false, "mandatory": true,  "default": 0 },
  "action":     { "type": "StepAction", "readOnly": false, "mandatory": true,  "default": "addLabel" },
  "params":     { "type": "object",     "readOnly": false, "mandatory": false, "default": {} },
  "haltOnFail": { "type": "boolean",    "readOnly": false, "mandatory": false, "default": false },
  "recipe":     { "type": "Recipe",     "readOnly": false, "mandatory": false, "default": "" },
  "execute":    { "params": [ { "name": "item", "type": "Item", "mandatory": true } ], "result": "Item" }
}
```

### Label
```json
{
  "_id": "KEEP-THE-EDITORS-ID",
  "_name": "Label",
  "_description": "Flat tag. No hierarchy — Jars do that job.",
  "name":  { "type": "string", "readOnly": false, "mandatory": true,  "default": "" },
  "tint":  { "type": "string", "readOnly": false, "mandatory": false, "default": "" },
  "items": { "type": ["Item"], "readOnly": false, "mandatory": false, "default": [] }
}
```

### Batch
```json
{
  "_id": "KEEP-THE-EDITORS-ID",
  "_name": "Batch",
  "_description": "A set of Items handled together — one Recipe run, one export, one Seal.",
  "status":     { "type": "string",   "readOnly": false, "mandatory": true,  "default": "queued" },
  "createdAt":  { "type": "date",     "readOnly": true,  "mandatory": true,  "default": "1970-01-01T00:00:00.000Z" },
  "finishedAt": { "type": "date",     "readOnly": false, "mandatory": false, "default": "1970-01-01T00:00:00.000Z" },
  "recipe":     { "type": "Recipe",   "readOnly": false, "mandatory": false, "default": "" },
  "items":      { "type": ["Item"],   "readOnly": false, "mandatory": false, "default": [] },
  "onFinished": { "params": [ { "name": "batch", "type": "Batch" } ] }
}
```

### NetRelish (already exists — confirm it reads exactly this)
```json
{
  "_id": "KEEP-THE-EDITORS-ID",
  "_name": "NetRelish",
  "_description": "The workbench. Root of the system.",
  "tagline":   { "type": "string",   "readOnly": true,  "mandatory": false, "default": "Savor the web. Get more done." },
  "brine":     { "type": ["Item"],   "readOnly": false, "mandatory": false, "default": [] },
  "jars":      { "type": ["Jar"],    "readOnly": false, "mandatory": false, "default": [] },
  "recipes":   { "type": ["Recipe"], "readOnly": false, "mandatory": false, "default": [] },
  "labels":    { "type": ["Label"],  "readOnly": false, "mandatory": false, "default": [] },
  "activeJar": { "type": "Jar",      "readOnly": false, "mandatory": false, "default": "" },
  "capture":   { "params": [ { "name": "url",    "type": "string", "mandatory": true } ], "result": "Item" },
  "seal":      { "params": [ { "name": "item",   "type": "Item",   "mandatory": true } ], "result": "Item" },
  "runRecipe": { "params": [ { "name": "recipe", "type": "Recipe", "mandatory": true },
                             { "name": "items",  "type": ["Item"], "mandatory": true } ], "result": "Batch" },
  "onCapture": { "params": [ { "name": "item",   "type": "Item" } ] },
  "onSeal":    { "params": [ { "name": "item",   "type": "Item" } ] }
}
```

**Checkpoint:** on the diagram, the Item box reads `kind : ItemKind`, `jar : Jar`,
`seal() : Item`. The NetRelish box reads `capture(url : string) : Item`. No `any` and no
`_Component` anywhere on any box.

---

## 4 · Behaviors — seven bodies

Two already have real bodies (`start`, `NetRelish.seal`). Five are still empty stubs
(`let result = ''`). Open each from the place in the table, replace the **entire card**
with the body below, click ✓. Do not nest it inside the stub. Do not click ✕.

| Behavior | Where to open it | Signature you should see | Status |
|---|---|---|---|
| `start` | Behaviors tab → **+** → On: `start` | `function start()` | ✅ done |
| `NetRelish.seal` | Models → NetRelish box → blue `seal` | `function seal(item)` | ✅ done |
| `NetRelish.capture` | Models → NetRelish box → blue `capture` | `function capture(url)` | ⬜ empty |
| `NetRelish.runRecipe` | Models → NetRelish box → blue `runRecipe` | `function runRecipe(recipe, items)` | ⬜ empty |
| `Item.seal` | Models → Item box → blue `seal` | `function seal()` — **no parameter** | ⬜ empty |
| `Recipe.run` | Models → Recipe box → blue `run` | `function run(items)` | ⬜ empty |
| `Step.execute` | Models → Step box → blue `execute` | `function execute(item)` | ⬜ empty |

Your existing empty cards for `Item.seal`, `Recipe.run`, and `Step.execute` should
reattach once those models exist again. If clicking the blue name says it already exists,
click into the existing card instead.

### start ✅
```javascript
function start() {
  const NetRelish = this.require('NetRelish');
  if (!this.require('pantry')) {
    new NetRelish({ _id: 'pantry' });
  }
}
```

### NetRelish.capture
```javascript
function capture(url) {
  const Item = this.require('Item');
  const now = new Date();
  const item = new Item({
    kind: 'page',
    state: 'brined',
    title: url,
    url: url,
    domain: new URL(url).hostname,
    source: 'browse',
    createdAt: now,
    updatedAt: now
  });
  this.brine().push(item);
  this.onCapture(item);
  return item;
}
```

### NetRelish.seal ✅  (has the `item` parameter)
```javascript
function seal(item) {
  item.seal();
  this.onSeal(item);
  return item;
}
```

### NetRelish.runRecipe
```javascript
function runRecipe(recipe, items) {
  return recipe.run(items);
}
```

### Item.seal  (no parameter — this is the one-way move)
```javascript
function seal() {
  if (this.state() === 'sealed') return this;
  const now = new Date();
  this.state('sealed');
  this.sealedAt(now);
  this.updatedAt(now);
  this.onSealed(this);
  return this;
}
```

### Recipe.run
```javascript
function run(items) {
  const Batch = this.require('Batch');
  const batch = new Batch({ status: 'running', createdAt: new Date(), recipe: this, items: items });
  const steps = this.steps().sort((a, b) => a.order() - b.order());
  for (const item of items) {
    for (const step of steps) {
      try {
        step.execute(item);
      } catch (e) {
        if (step.haltOnFail()) {
          batch.status('failed');
          batch.finishedAt(new Date());
          this.onRunFinished(batch);
          return batch;
        }
      }
    }
  }
  batch.status('done');
  batch.finishedAt(new Date());
  this.lastRunAt(new Date());
  this.onRunFinished(batch);
  return batch;
}
```

### Step.execute
```javascript
function execute(item) {
  const params = this.params() || {};
  switch (this.action()) {
    case 'addLabel': {
      const labels = item.labels();
      if (params.label && !labels.includes(params.label)) labels.push(params.label);
      item.labels(labels);
      break;
    }
    case 'removeLabel': {
      item.labels(item.labels().filter(l => l !== params.label));
      break;
    }
    case 'moveToJar': {
      item.jar(params.jar);
      item.state('jarred');
      break;
    }
    case 'seal': {
      item.seal();
      break;
    }
    default: {
      // summarize, extractLinks, extractTasks, ocrImage, exportMarkdown,
      // exportPDF, runShortcut, notify: performed on-device by the app,
      // reading the sealed snapshot only. Nothing to model here.
      break;
    }
  }
  item.updatedAt(new Date());
  return item;
}
```

**Checkpoint:** Behaviors tab → the Models list on the right shows `NetRelish`, `Item`,
`Recipe`, `Step`. Seven cards total, none containing `let result = ''`.

---

## 5 · Components tab — four seed records

Components reference each other by `_id`, so create them **in this order**. For each:
**+** → pick the model → Create → select all → paste → ✓.

Model **Jar**:
```json
{ "_id": "read-later", "name": "Read Later", "glyph": "nr-jar", "isPinned": true, "sortOrder": 0, "shelfLifeDays": 3 }
```

Model **Jar**:
```json
{ "_id": "reference", "name": "Reference", "glyph": "nr-jar", "isPinned": false, "sortOrder": 1, "shelfLifeDays": 7 }
```

Model **Recipe**:
```json
{ "_id": "seal-summarize", "name": "Seal & Summarize", "trigger": "onSeal", "isShortcutExposed": true }
```

Model **NetRelish** (the singleton that `start` looks for — the `_id` must be exactly `pantry`):
```json
{ "_id": "pantry", "jars": ["read-later", "reference"], "recipes": ["seal-summarize"], "activeJar": "read-later" }
```

---

## 6 · Export

Export the system as JSON (the same way you produced the last file) and save it as
`NetRelish.json`. Drop it in the repo at `/design/NetRelish.json` — or just send it in
chat and it gets placed there.

**Done looks like** — open the exported JSON and check:

- [ ] `types` has 5 entries
- [ ] `schemas` has 7 entries: NetRelish, Item, Jar, Recipe, Step, Label, Batch
- [ ] `models` has 7 entries, same names, no `"type": "any"` anywhere
- [ ] `behaviors` has 7 entries and none contains `let result = ''`
- [ ] `components` has 4 entries: `read-later`, `reference`, `seal-summarize`, `pantry`

Then Prompt 3 runs: `Sources/Pantry/Models/*.swift` as GRDB records, `Migrations/V1.swift`
with FTS5, the `SealIntent` and `CaptureIntent` App Intents, and tests — all generated from
this file, none of it hand-written. The mapping is in `CLAUDE.md` (Schema → Swift).

---

## When something goes wrong

| Symptom | Cause | Fix |
|---|---|---|
| "property 'name' is missing" | Pasted a Schema/Model block into Types, or vice versa | Types use `name`; Schemas and Models use `_name` |
| Error on line 1 | Wrong language for the tab | JSON everywhere except Behaviors (JavaScript) |
| Create fails: name exists | It was created before | Click it in the right-hand list and edit there |
| A model or behavior vanished | ✕ was clicked | ✕ deletes. Recreate it; matching-name behavior cards reattach |
| `seal` body rejected | Pasted into the wrong `seal` | `NetRelish.seal(item)` has a parameter; `Item.seal()` has none |
| Box on the diagram still shows `any` | Model JSON not saved | Re-open the model, paste, restore `_id`, ✓ |
