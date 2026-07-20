# Sidebar document switching — UX analysis

**Status:** Proposed direction
**Scope:** Persistent sidebar, recent-document behavior, agent updates, and fast
document switching
**Primary recommendation:** Stable Open working set + Updates + transient Quick
Switcher

## Summary

The current Recents behavior should change. Recency is a useful signal, but bmd
turns recency into immediate physical movement: opening a recent document removes
it from its row and reinserts it at the top of the list.

That movement destroys the spatial information the user just relied on. The
pointer remains over the old row, but the row now contains a different document.
This is especially disorienting when switching repeatedly among a small working
set.

The recommended direction is to:

1. Replace persistent Recents with a stable **Open** working set.
2. Replace Watched with **Updates**, focused on unseen agent activity.
3. Keep the selected document in place and change only its highlight.
4. Move chronological history into a transient Quick Switcher and the menu bar.
5. Add Back and Forward commands for rapid document toggling.
6. Keep Projects as the stable location-oriented view.

This gives the sidebar three unambiguous jobs:

```text
OPEN       What am I actively reading?
UPDATES    What did an agent change?
PROJECTS   Where do my documents belong?
```

## Lightweight UX optimization charter

No prior UX charter exists for bmd, so this analysis derives one from the
product vision and current use.

### User and context

- The primary user works with coding agents frequently throughout the day.
- The primary platform is macOS with mouse, trackpad, and keyboard input.
- The primary task is reopening one of a small number of active Markdown
  documents.
- Opening the wrong document is immediately reversible and does not require a
  confirmation step.

### Optimization priorities

1. Preserve flow and spatial stability.
2. Make repeated document switching fast.
3. Favor recognition while offering keyboard accelerators for practiced users.
4. Surface agent-created and agent-modified documents without making the
   persistent interface move unexpectedly.
5. Keep persistent navigation predictable; place dynamic ranking in transient
   interfaces.

The governing principle is:

> Preserve the user's spatial map before optimizing the sort order.

## Primary task model

### Goal

Reopen the document most likely to be relevant now.

### Current task hierarchy

```text
0. Open a likely document
   1. Decide which section may contain it
      - Watched
      - Recents
      - Projects
   2. Scan filenames and project context
   3. Point to and click the document
   4. Verify the correct document opened
   5. Reorient after Recents changes order
```

The task does not exceed the normal working-memory capacity of roughly four
active chunks. The more important failure is that bmd invalidates its own
external memory. Row position could help the user remember where a document is,
but immediate reordering removes that aid after every selection.

## Current-state findings

### 1. Clicking destroys the information used to click

The current implementation removes the clicked document from Recents and
reinserts it at index zero.

Before selecting `welcome.md`:

```text
README.md
welcome.md
rendering-showcase.md
```

Immediately after selecting it:

```text
welcome.md
README.md
rendering-showcase.md
```

The pointer remains over the second row, but that row is now `README.md`. This
creates a moving-target capture risk and prevents spatial learning.

**Severity:** Major
**Frequency:** Frequent
**Confidence:** High; confirmed in the implementation

### 2. The same document occupies several semantic roles

In the analyzed screenshot, twelve visible rows represent only six unique
documents. A document may appear under Watched, Recents, and Projects.

Those sections are intended to answer different questions:

- Watched: what did an agent change?
- Recents: what did I open?
- Projects: where does the document belong?

Visually, they compete as three ways to open the same thing. The user must first
choose a section and then choose a document.

For five Recents, Hick-Hyman predicts an equiprobable choice time of:

```text
200 + 150 × log₂(6) = 588 ms
```

Treating all twelve visible document rows as unstructured alternatives produces
an upper bound of approximately 755 ms. Section grouping reduces that cost, but
duplicate representations still increase scanning and uncertainty.

**Severity:** Major
**Frequency:** Frequent
**Confidence:** Medium; item counts are measured from the screenshot, while
effective decision entropy depends on user familiarity

### 3. Target size is not the primary problem

The rows are approximately 30–40 points high and occupy most of the sidebar
width. Fitts's Law predicts an ordinary pointing cost of roughly 200–400 ms,
depending on where the pointer begins.

The larger penalty occurs after selection:

- the list changes;
- the user notices the change;
- the user reconstructs the ordering;
- the user reacquires the next target.

Two or three additional visual fixations cost roughly 460–690 ms. A new mental
preparation operator adds approximately 1.35 seconds. Unexpected movement can
therefore add around 1.8–2.0 seconds to a subsequent switch, excluding slips and
recovery.

**Confidence:** Medium; timing uses standard KLM and MHP values with screenshot
geometry

## Alternative A — Current document plus history

This is the smallest conceptual change.

```text
CURRENT
▍ README.md
  bmd

RECENT
  welcome.md
  rendering-showcase.md
  UBIQUITOUS_LANGUAGE.md

WATCHED
  agent-report.md              new
  implementation-plan.md      modified

PROJECTS
  platform
```

After selecting `welcome.md`:

```text
CURRENT
▍ welcome.md

RECENT
  README.md
  rendering-showcase.md
  UBIQUITOUS_LANGUAGE.md
```

The previous document takes the first Recent position. Clicking that same
physical row switches back, making two-document comparison efficient.

### Predicted interaction cost

- First switch: approximately 2.0–3.2 seconds.
- Switch back to the previous document: approximately 1.3–2.1 seconds.
- Peak working-memory load: 1–2 chunks.
- Moving-target risk: medium, but the movement becomes a predictable swap.

### Tradeoff

Deeper history still moves. Current may also duplicate a document represented
under Watched or Projects.

## Alternative B — Stable Open working set

This is the preferred persistent-sidebar model.

```text
OPEN
▍ README.md                    bmd
  welcome.md                   examples
  rendering-showcase.md        examples
  UBIQUITOUS_LANGUAGE.md       platform

UPDATES                                      2
• agent-report.md              modified 1m
• implementation-plan.md       new 4m

PROJECTS
⌄ platform
    playground-inspector-control…
    media-source-encoded.md
```

### Interaction rules

- Opening a document adds it to Open.
- Clicking an Open document changes only the selection highlight.
- Open documents never reorder themselves.
- Users can remove, pin, or manually reorder documents.
- Keep the visible working set compact—approximately five to seven documents.
- If an open document changes, show an unread-change indicator on its existing
  row instead of duplicating it under Updates.
- Updates contains agent-created or agent-modified documents not already
  represented in Open.

Stable positions become external memory. With practice, the user can point
toward a learned location before fully rereading the filename.

### Predicted interaction cost

- Practiced repeated switch: approximately 1.6–2.7 seconds.
- Reorientation penalty: eliminated.
- Peak working-memory load: approximately one chunk.
- Hick-Hyman remains within the safe range while Open contains seven or fewer
  visible items.
- Moving-target risk: low.

### Tradeoff

Open becomes a small workspace with lifecycle rules. The design must define
when documents leave it and make Remove or Close discoverable without adding
noise.

## Alternative C — Transient Quick Switcher and navigation history

This removes dynamic history from the persistent sidebar.

```text
Sidebar
────────────────────────
CURRENT
▍ README.md

UPDATES
• agent-report.md
• implementation-plan.md

PROJECTS
⌄ platform
```

A keyboard command opens a temporary switcher:

```text
┌ Switch Document ──────────────────────────┐
│ Search files…                             │
├───────────────────────────────────────────┤
│ README.md                       bmd        │
│ welcome.md                      examples   │
│ rendering-showcase.md           examples   │
│ UBIQUITOUS_LANGUAGE.md          platform   │
└───────────────────────────────────────────┘
```

### Interaction rules

- `⌘[` and `⌘]` navigate Back and Forward through document history.
- A Quick Switch command such as `⌘⇧O` opens the transient switcher.
- Search spans open documents, history, updates, and project documents.
- Recency ranking is safe inside the switcher because it closes after
  selection; the user never watches its rows move.

### Predicted interaction cost

- Back to the previous document: approximately 1.3–2.0 seconds.
- Arbitrary recent document through the switcher: approximately 1.8–3.0
  seconds.
- Peak working-memory load: 1–2 chunks.
- Scalability: high; typing reduces choice entropy for large collections.

### Tradeoff

Keyboard navigation has a discovery cost. Visible Back and Forward controls and
menu commands should remain available as recognition-based paths.

## Alternative D — Predictive “Likely next” ranking

bmd could rank documents using recency, frequency, active project, and recent
agent changes.

Predictive ranking should not control a persistent list. Reducing five choices
to three improves Hick-Hyman decision time from approximately 588 ms to 500 ms,
a gain of only 88 ms. That is much smaller than the roughly 1.8-second
reorientation cost created when visible rows move.

Predictive ranking could still be valuable inside the transient switcher, where
reordering happens while the interface is closed.

## Comparison

| Model | Repeated switch | Stable positions | Scalability | Learnability |
|---|---:|---|---|---|
| Current Recents | 3.0–5.0s after movement | Poor | Poor | High |
| Current + History | 1.3–2.1s for switch-back | Moderate | Moderate | High |
| Stable Open | 1.6–2.7s | Excellent | Moderate | High |
| Quick Switcher | 1.3–3.0s | Excellent | Excellent | Medium |

The timing estimates have medium confidence and approximately ±20% absolute
accuracy. Relative comparisons are more reliable than the precise totals.

### Sensitivity by user profile

- **Novice:** Stable Open is strongest because every action remains visible and
  the layout does not move.
- **Intermediate:** Stable Open remains strongest for common switching; the
  Quick Switcher becomes useful as the project set grows.
- **Expert:** The hybrid model wins. Stable Open handles visual switching, while
  Back and Forward minimize two-document toggling cost.
- **Power user:** Keyboard history is fastest for the immediately previous
  document; the stable sidebar remains the recovery and recognition surface.

Mobile is intentionally excluded because bmd is a macOS desktop application.

## Recommendation

Adopt a hybrid of Alternatives B and C:

1. Replace Recents with a stable **Open** section.
2. Highlight the current document in place without moving it.
3. Replace Watched with **Updates**, focused specifically on unseen agent
   activity.
4. Never duplicate an open document under Updates; add a change indicator to
   its Open row.
5. Keep chronological history in the menu bar and a Quick Switcher.
6. Add document Back and Forward commands for rapid toggling.
7. Keep Projects as the stable location-oriented view.

At 30–60 document switches per day, eliminating 1.5 seconds of reorientation
per switch saves approximately 3–6 hours per user per year. More importantly,
it removes an interruption from the workflow bmd is designed to protect.

## Interaction-state model

```text
                         open/select
       ┌──────────────────────────────────────┐
       │                                      ▼
[Project file] ──open──▶ [Open working set] ──select──▶ [Current document]
       ▲                         ▲                              │
       │                         │                              │ changed
       │                         │ open                         ▼
       │                    [Update item] ◀──────────── [Change detected]
       │                         │
       └──────── reveal ─────────┘

[Current document] ──Back/Forward──▶ [History position]
[Any document source] ──────────────▶ [Quick Switcher index]
```

### Required invariants

- Selecting an existing Open document never changes row order.
- A document has one primary persistent representation.
- The current document is always visually identifiable.
- A changed Open document receives an update state in place.
- New external activity never moves a target between pointer-down and
  pointer-up.
- Back and Forward preserve independent document scroll positions when
  practical.
- Every keyboard accelerator has a visible menu or button equivalent.

## Decisions required before implementation

### Open-document lifecycle

- Does opening a document add it to the top or bottom of Open?
- Should Open be capped at five, seven, or a configurable count?
- When the cap is reached, should bmd remove the least-recently-used unpinned
  document or ask the user?
- Should Open persist across launches?
- Are pinning and manual ordering needed in the first iteration?

### Update lifecycle

- What counts as unread: created, modified, or both?
- When is an update considered read: on open, after remaining visible for a
  period, or by explicit dismissal?
- Should read items remain until the pointer leaves the section or until the
  next session to avoid moving targets?
- Should multiple updates to the same document collapse into one item?

### History and navigation

- Should Back and Forward track every selection or collapse repeated adjacent
  documents?
- Should history persist across launches?
- Does returning to a document restore its last scroll position?
- What shortcut should open Quick Switch without conflicting with macOS
  conventions?

### Migration

- Existing Recents can seed the initial Open working set.
- Existing Watched activity can seed Updates, but current/open duplicates must
  collapse into in-place status indicators.
- Existing project-file history can remain under Projects.

## Proposed implementation sequence

1. Define and test the Open, Updates, current-selection, and history state
   model.
2. Replace immediate most-recently-used reordering with stable Open ordering.
3. Merge duplicate update state into Open rows.
4. Add Back and Forward history with menu commands and shortcuts.
5. Add the Quick Switcher across Open, Updates, history, and Projects.
6. Evaluate the rendered sidebar with five, seven, and twenty active documents.
7. Validate the design through repeated A→B→A switching and simultaneous agent
   update scenarios.

## Evaluation limitations

- KLM and GOMS estimate practiced, error-free behavior and are most reliable for
  relative comparisons.
- Novice timing is extrapolated and less precise than expert timing.
- The models capture interaction cost, not satisfaction, trust, or visual
  delight.
- Absolute timing predictions should be treated as approximately ±20%.
- The recommended model should be validated with real repeated switching after
  a prototype exists.
