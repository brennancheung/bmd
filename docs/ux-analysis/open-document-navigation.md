# Open-document ordering and keyboard navigation

**Status:** Implemented
**Scope:** Open ordering, direct document shortcuts, sequential navigation, and
Back/Forward history
**Implemented direction:** Treat Open as a stable vertical tab strip, while
keeping visit history as a separate, explicitly labeled navigation model.

## Executive summary

Before this change, the Open section was not sorting itself by recency. It
already behaved mostly like a stable vertical tab strip:

- a newly opened document is appended to the bottom;
- reopening an existing document updates `lastViewedAt` without moving its row;
- the selected document is highlighted in place;
- the order persists across launches;
- Close and Move Up/Down change the order explicitly.

Two behaviors broke or obscured that stability:

1. Once Open exceeds its configured limit, bmd silently removes the
   least-recently-viewed unpinned document. Removing a middle row shifts every row
   beneath it.
2. `[` and `]` do not traverse Open. They traverse a separate chronological
   visit history. The toolbar calls these controls “Previous Document” and “Next
   Document,” which implies spatial adjacency even though the implementation means
   temporal Back and Forward.

For example:

```text
Open position:     1 A     2 B     3 C     4 D
Visit sequence:      A  →    D  →    B

Current: B (position 2)
[ target: D (position 4)
[ target: A (position 1)
] target: D (position 4)
```

The rows are stable, but the keyboard target jumps between them because the
shortcut follows time rather than position. That is the main source of the
“random” feeling.

The recommended model is:

```text
Open position             Visit history
stable spatial order      chronological order
⌘1…⌘9 direct access       [ / ] Back / Forward
Tab / ⇧Tab adjacent       explicitly labeled as history
```

This gives each ordering one job and makes the result of every shortcut
predictable before it is invoked.

## Existing optimization charter

This analysis extends the charter in `sidebar-document-switching.md`:

1. Preserve flow and spatial stability.
2. Make repeated document switching fast.
3. Favor recognition while offering accelerators for practiced users.
4. Keep persistent navigation predictable.
5. Put dynamic ranking in transient interfaces.

The governing principle remains:

> Preserve the user's spatial map before optimizing the sort order.

## Previous implementation

### Open ordering

The current Open order is insertion order with explicit exceptions:

1. A new document appends to the bottom.
2. Selecting an existing Open document does not move it.
3. Move Up and Move Down reorder it explicitly.
4. Closing a document removes its row.
5. Lowering the Open limit removes least-recently-viewed unpinned rows.
6. Opening a new document at the limit removes the least-recently-viewed
   unpinned row other than the new document.
7. Pinned documents are protected from automatic eviction.

This is stable enough for spatial anchors until automatic eviction occurs. At a
limit of `N`, removing a row at position `j` reassigns `N - j` positions. If the
evicted row were uniformly distributed, the expected number of shifted rows would
be `(N - 1) / 2`: **4.5 shifted positions at N = 10**. The exact distribution is
usage-dependent, but a single hidden eviction can invalidate several learned
number mappings.

Closing and manual reordering also change positions, but these are visible,
causal actions. Users can update their spatial model from the action they just
took. Silent eviction lacks that causal feedback.

### History ordering

History is a chronological sequence of document selections:

- repeated adjacent selections of the current document are collapsed;
- Back decrements a history cursor;
- Forward increments it;
- selecting a document after going Back discards the forward branch;
- deleted files are skipped;
- history persists across launches.

This is standard browser-style history. It is useful for returning to a document
the user just left, but it is not a representation of Open order.

### Naming mismatch

The menu labels the commands Back and Forward, but the toolbar help says
“Previous Document” and “Next Document.” “Previous” can reasonably mean either:

- the previous row in Open; or
- the previous document in visit history.

That stimulus-response incompatibility makes the user predict a spatial target
for a temporal command.

## Task and cognitive model

### Primary goal

Switch to an active Markdown document without searching for it again or losing
the user's place in the working set.

### Task hierarchy

```text
0. Switch document
   Plan: choose one method based on what the user knows about the target

   1. Target is visible and recognized
      1.1 Find its stable Open row
      1.2 Click it
          CTA: 1–2 chunks; low error if rows remain stable

   2. Target's stable position is learned
      2.1 Recall or recognize its number
      2.2 Press ⌘ plus that number
          CTA: 1–2 chunks; mapping must remain visible and stable

   3. Target is adjacent in Open
      3.1 Press next/previous Open shortcut
          CTA: 1 chunk; position determines the result

   4. Target is the document visited immediately before/after
      4.1 Press Back/Forward
          CTA: 1–2 chunks if the visit sequence is remembered;
               otherwise target prediction requires recall or verification

   5. Target is not in the active set or its position is unknown
      5.1 Open Quick Switcher
      5.2 Search by filename or path
      5.3 Select result
```

The current design exposes methods 1, 4, and 5. It lacks a distinct method for
adjacent Open navigation, and method 4 is described with language that sounds like
method 3.

## Information design

### User goal

The user needs to see the active working set, identify the current document,
predict the destination of a navigation command, and switch with one action.

### Information inventory

- **Primary:** document identity, stable Open position, current selection.
- **Secondary:** project-relative path, pin state.
- **Conditional:** unread disk update, keyboard chord while Command is held.
- **Hidden/omitted:** last-viewed timestamps, passive section counts, chronological
  ranking inside the persistent list.

The position number is not analogous to the passive counts that were removed from
section headers. A section count merely reports state; an ordinal is an actionable
address. It earns its visual space only if `⌘N` reliably activates that address.

### Semantic groups

- **Document identity:** icon, filename, relative path.
- **Spatial address:** position and its keyboard shortcut.
- **Current state:** selection highlight.
- **Exception state:** unread update dot.
- **Lifecycle actions:** pin, reorder, close; kept in the context menu.
- **Temporal navigation:** Back/Forward; visually and verbally separated from the
  Open row order.

### Visual hierarchy

- The filename and current selection remain primary.
- The shortcut is absent during normal reading and appears as a trailing overlay
  only while Command is held.
- Project path remains secondary.
- Holding Command reveals `⌘1` through `⌘9` over the trailing edge without
  changing row geometry.
- Update state remains a small exception indicator.

## Quantitative interaction analysis

### Direct selection

The following KLM ranges use a fast practiced profile (`M = 1.20s`, `K = 0.12s`,
`P = 0.80s`) and a slower novice profile (`M = 1.50s`, `K = 0.50s`,
`P = 1.30s`). System response is excluded because it is shared by the alternatives.

| Method | Operators | Fastman | Slowman | Peak WM |
|---|---|---:|---:|---:|
| Click a visible Open row | `M P K` | 2.12s | 3.30s | 1–2 chunks |
| Press a learned `⌘N` | `M K` | 1.32s | 2.00s | 1–2 chunks |
| First adjacent shortcut | `M K` | 1.32s | 2.00s | 1 chunk |
| Each anticipated repeated adjacent step | `K` | 0.12s | 0.50s | 1 chunk |

Direct numbering saves approximately **0.8–1.3 seconds** over pointing when the
mapping is known. Confidence is **Medium**: the relative operator difference is
strong, but absolute KLM times are normally accurate only to about ±20%.

### Choice and scan cost

Hick-Hyman predicts the following reaction times for an unstructured choice:

| Visible Open documents | Predicted choice time |
|---:|---:|
| 5 | 588ms |
| 9 | 698ms |
| 10 | 719ms |

All remain below the 800ms flag threshold, so nine visible positions are viable.
Stable alignment and learned ordinals reduce the need to treat every row as an
equiprobable choice. They turn the task from list search into direct address
retrieval.

### Working memory and hidden-mode cost

Requiring the user to remember nine filename-to-number mappings would exceed the
four-chunk active working-memory guideline. The Command-held overlay externalizes
the mapping on demand, while the Navigate menu provides a persistent discovery
path. The immediate switching task remains at roughly 1–2 chunks.

Showing numbers only while Command is held introduces a mode dependency. The
skill's error model assigns a 10% mode-error risk to mode-dependent behavior. That
does not mean 10% of switches will fail in production; it is a pattern-level risk
signal. After using the first implementation, the persistent gutter proved more
costly than the theoretical discoverability benefit: it indented every Open row
and made shortcut metadata compete with filenames. The implemented refinement
therefore uses a trailing `⌘N` overlay only while Command is held. The overlay
temporarily covers the update indicator and reserves no permanent space.

### History uncertainty

When the user remembers the immediately previous document, Back is as fast as any
single shortcut: approximately 1.32–2.00 seconds. When the target is uncertain,
the user must reconstruct the visit sequence and verify the result. One mental
cycle plus 1–3 visual fixations adds roughly 1.43–2.19 seconds, yielding an
estimated **2.75–4.19 seconds**. Confidence is **Medium-Low** because uncertainty
frequency depends on real use.

The solution is not to remove history automatically. It is to label history as
history and provide a different command for spatial traversal.

### Annualized impact

If the user switches documents 30–60 times per workday and direct numbered access
is used for half of those switches, saving 0.8–1.3 seconds per applicable switch
produces approximately:

```text
Low:  30 × 50% × 0.8s × 250 days = 3,000s  = 0.8 hours/year
High: 60 × 50% × 1.3s × 250 days = 9,750s  = 2.7 hours/year
```

The larger benefit is interruption reduction: the destination becomes predictable
before activation, so the user does not need to inspect the result and reconstruct
where the document moved.

## Design directions

### Option A — Stable vertical tabs with separate history

Best when Open is a persistent working set and long filenames/project paths matter.

```text
OPEN
    CONTEXT.md                         docs
    rendering-showcase.md              examples       •
    welcome.md                         examples
    sidebar-document-switching.md      docs/ux-analysis
    README.md                          bmd

Holding Command (same geometry):

    CONTEXT.md                         docs          ⌘1
    rendering-showcase.md              examples      ⌘2
    welcome.md                         examples      ⌘3
```

Interaction rules:

- New documents append to the bottom.
- Existing documents never move when selected.
- The first nine visible positions have `⌘1…⌘9` addresses.
- `Tab` and `⇧Tab` traverse adjacent Open positions.
- `[` and `]` remain Back and Forward **in document history**, with `⌘[` and
  `⌘]` retained as aliases.
- Back/Forward tooltips and menu text use the word “history.”
- Automatic LRU eviction is removed or changed to an explicit/soft-limit cleanup.
- Close and manual reorder may renumber rows because the causal action is visible.
- Documents beyond position nine remain accessible by click and Quick Switcher;
  manual reorder can promote one into the numbered zone.

Regions:

- Center: document identity and project context.
- Row background: current state.
- Right edge: update state normally; shortcut overlay while Command is held.
- Toolbar/menu: temporal history, separate from Open order.

HCI checks:

- **WM:** 1–2 chunks because the number mapping is externalized. Pass.
- **Hick:** 698ms at nine choices. Pass.
- **KLM:** direct learned target 1.32–2.00s. Best arbitrary-target path.
- **Error:** low after automatic eviction is removed; explicit Close/Reorder remains
  the only routine source of renumbering.

Tradeoffs:

- Adds a narrow column of visual ink.
- Users must learn the distinction between spatial traversal and temporal history.
- Positions are stable, not permanent identifiers; explicit close/reorder changes
  them just as closing/reordering a browser tab does.

### Option B — Horizontal browser tabs

Best when the tab metaphor must be unmistakable and only a few short filenames are
open.

```text
┌ CONTEXT.md × ┬ rendering… × ┬ welcome.md × ┬ + ┐
└──────────────┴───────────────┴──────────────┴───┘

UPDATES
...

PROJECTS
...
```

Regions:

- Top strip: current working set, close/reorder, positional shortcuts.
- Sidebar: Updates and Projects only.
- Overflow menu: tabs that do not fit.

HCI checks:

- **Learnability:** high because it closely matches browsers and editors.
- **Fitts:** wide horizontal targets are easy while visible.
- **Hick/scan:** degrades after overflow because visible and hidden tabs become two
  search regions.
- **WM:** project context disappears or must move into tooltips/secondary UI.

Tradeoffs:

- Long Markdown filenames truncate aggressively.
- Project-relative context becomes difficult to show.
- Overflow destroys the promised one-glance working set.
- Consumes vertical document space while duplicating a navigation surface already
  present in the sidebar.

### Option C — History-first MRU switcher

Best when the dominant behavior is repeatedly toggling between the two most
recent documents rather than maintaining stable positional anchors.

```text
Hold navigation chord:

┌ Recent documents ───────────────────────┐
│ 1  rendering-showcase.md       examples │
│ 2  CONTEXT.md                  docs     │
│ 3  README.md                   bmd      │
└─────────────────────────────────────────┘

Open remains stable in the sidebar, but shortcuts follow MRU order.
```

Regions:

- Transient overlay: chronological switching and number hints.
- Sidebar Open: recognition/recovery, not shortcut addressing.
- Projects: location.

HCI checks:

- **KLM:** immediate switch-back can be 1.32–2.00s.
- **WM:** 1 chunk for the immediately previous document; 2–4 for deeper history.
- **Error:** medium for arbitrary targets because MRU positions change after every
  selection.
- **Interruption:** weaker than stable positions; the user must inspect the overlay
  before deeper selection.

Tradeoffs:

- Excellent A↔B toggling.
- Reintroduces dynamic ordering, but safely inside a transient surface.
- Does not solve the user's desire for fixed numeric anchors.

## Comparison

| Dimension | A: Vertical stable tabs | B: Horizontal tabs | C: MRU switcher |
|---|---|---|---|
| Direct expert target | 1.32–2.00s | 1.32–2.00s | 1.32–2.00s only for recent targets |
| Visible filename/path capacity | High | Low | Medium |
| Spatial stability | High | Medium-high until overflow | Low by design |
| Peak WM | 1–2 chunks | 1–2 chunks | 2–4 chunks for deeper history |
| Learnability | Medium-high | High | Medium |
| Arbitrary-target predictability | High for positions 1–9 | High while visible | Low-medium |
| Handles 10+ documents | Sidebar + switcher | Overflow required | Search/ranking |
| Fits current bmd structure | High | Low | Medium |

### Sensitivity by profile

- **Novice:** Option B's familiar tabs are easiest to recognize. Option A preserves
  a visible current state, while its menu commands teach the hidden shortcuts.
- **Intermediate:** Option A best balances recognition, project context, and direct
  shortcuts.
- **Expert:** Option A wins for deterministic direct access; Option C wins only for
  an immediately previous A↔B toggle.
- **Power user:** Option A plus adjacent traversal provides the lowest predictable
  cost across both keyboard and pointer workflows.
- **Mobile:** Not applicable; bmd is a macOS desktop application. A future touch
  design would require at least 44×44pt targets and should be evaluated separately.

## Implemented recommendation

bmd now uses **Option A: stable vertical tabs with separate history**.

The current Open section already has most of the right lifecycle behavior. It does
not need to look like a row of browser tabs. It needs to *behave* like a vertical
tab strip:

1. Preserve append-only order during normal opening and selection.
2. Remove hidden LRU eviction from the active numbered set.
3. Give the first nine positions direct keyboard addresses.
4. Show trailing `⌘N` overlays only while Command is held, with no permanent
   gutter or layout shift.
5. Add a separate previous/next **Open position** command.
6. Keep chronological Back/Forward, but explicitly call it document history.
7. Retain Quick Switcher as the transient, dynamically ranked path for documents
   whose position is unknown.

This preserves the strengths of tabs—stable position, direct access, current-state
visibility—without importing their weakest desktop form: a cramped horizontal
strip of truncated filenames.

## Validation plan

Before finalizing the shortcut map, test these sequences with 5, 9, and 12 Open
documents:

1. Open A, B, C; switch A → C → B; predict every Back/Forward destination.
2. Switch repeatedly with `⌘N`; verify numbers never change on selection.
3. Add a tenth document; verify no numbered row moves silently.
4. Close position 3; verify the renumbering is immediately visible and understood.
5. Traverse adjacent rows in both directions; verify history remains independent.
6. Hold Command and use Copy/Open/Zoom shortcuts; check that shortcut hints do not
   flash distractingly or move row content.
7. Restart bmd; verify Open ordering and the current document remain coherent.

The design should be considered successful when a user can name the destination
of `⌘N`, adjacent traversal, Back, and Forward before pressing the keys.

## Limitations and confidence

- **High confidence:** current ordering/history diagnosis, based on implementation
  and tests.
- **Medium confidence:** relative KLM comparisons and the recommendation to
  separate spatial and temporal commands.
- **Low confidence:** ideal visual treatment and Command-hold timing until rendered
  and tried in the native app.
- KLM/GOMS model practiced, error-free use. Novice estimates are extrapolations.
- Absolute timing estimates are approximately ±20%; relative comparisons are more
  reliable.
- The analysis measures efficiency, memory, and error risk, not delight or trust.
- This narrows the design space; it does not replace repeated real-user use.
