# dooyou Design System

## 1. Atmosphere & Identity

dooyou is a quiet macOS command-center companion. It should feel like a small native utility that gives an immediate read on agent activity, system pressure, connectors, and account spend without making the user parse a dashboard. The signature is a warm mascot living inside precise desktop chrome: friendly motion on the menu bar, restrained status surfaces in the popover, and deeper management views in the dashboard.

## 1.1 Mascot Persona System

The mascot set must feel like three authored companions, not recolored icons. Each mascot starts from a real-world reference, then simplifies into a premium menu-bar sprite with readable silhouette at 18px. Do not add more visible mascot choices until these three reach the same quality bar.

### Dooyou

- Base reference: Coton de Tulear puppy.
- Role: active executor and friendly work companion.
- Personality: eager, soft, fast, lightly mischievous when the machine is busy.
- Silhouette: small fluffy body, rounded head, curled tail, short legs, cotton-cloud outline.
- Color: warm white fur with subtle cream shadows; black button nose/eye; green capsule background by default.
- Motion: bouncy run cycle. At high load, add tiny sweat drops and a faster stride, but keep the icon readable.
- UI label: `두유`.
- Quality rule: this is the benchmark. Other mascots must have the same authored-spec clarity before they ship.

### Cat

- Base reference: cream tabby domestic kitten with a compact body and upright ears.
- Role: calm analyst that watches usage patterns and system signals.
- Personality: focused, curious, quiet, a little smug when everything is healthy.
- Silhouette: triangular ears, arched tail, compact oval body, clear head/body break.
- Color: cream-orange body, darker tabby stripes only where readable at small size, dark eye/nose pixel.
- Motion: light trot with a tail flick. Do not make it look like a generic capsule or fox.
- UI label: `고양이`.
- Quality rule: ears and tail must identify it immediately even without reading the label.

### Turtle

- Base reference: baby Hermann tortoise.
- Role: long-horizon stability, limits, budgets, and slow-burn tracking.
- Personality: calm, reliable, patient, stubborn about safe limits.
- Silhouette: domed shell, tiny head forward, four low feet, short tail if space allows.
- Color: olive shell, soft green skin, warm shell panels with one or two readable seams.
- Motion: slow confident crawl. It should look intentionally slow, not under-animated.
- UI label: `거북이`.
- Quality rule: shell geometry must be the first read; legs/head are secondary.

### Shared mascot rules

- The visible set is exactly three: `두유`, `고양이`, `거북이`.
- All three use the same capsule background themes so the menu bar remains consistent.
- Mascots are small product UI assets, not decorative illustrations. Prioritize silhouette, contrast, and motion readability over detail.
- Any generated bitmap replacement must include four running/crawling frames, transparent background, and enough padding for a menu-bar capsule.

## 2. Color

### Palette

| Role | Token | Light | Dark | Usage |
| --- | --- | --- | --- | --- |
| Surface/primary | `surfacePrimary` | `#F7F5F1` | `#111214` | App and popover background |
| Surface/secondary | `surfaceSecondary` | `#EEEAE2` | `#1A1B1E` | Section grouping |
| Surface/elevated | `surfaceElevated` | `#FBFAF7` | `#222326` | Cards and rows |
| Text/primary | `textPrimary` | `#161719` | `#F4F4F2` | Titles, major values |
| Text/secondary | `textSecondary` | `#6F6A62` | `#A7A29A` | Captions, hints |
| Border/default | `borderDefault` | `#DED8CE` | `#34363A` | Dividers, panels |
| Accent/primary | `accentPrimary` | `#D26B45` | `#FF8A63` | Primary actions, dooyou warmth |
| Accent/info | `accentInfo` | `#3A6EA5` | `#6EA6DF` | Codex/info/focus |
| Status/success | `statusSuccess` | `#25A65A` | `#43C978` | Healthy/connected |
| Status/warning | `statusWarning` | `#D28A20` | `#F2AD3E` | Pressure/caution |
| Status/error | `statusError` | `#C84D3A` | `#F06A55` | Limits/errors |

### Rules

- Use color for semantic state first: green healthy, orange pressure, red critical, blue connector/focus.
- Warm accent is for dooyou identity and selected states, not for every chart.
- Popover surfaces stay translucent or tonal; avoid heavy borders around every row.

## 3. Typography

### Scale

| Level | Size | Weight | Line Height | Tracking | Usage |
| --- | --- | --- | --- | --- | --- |
| Display | 32px | 700 | 1.08 | 0 | Dashboard totals |
| H1 | 24px | 700 | 1.16 | 0 | Dashboard section title |
| H2 | 18px | 650 | 1.22 | 0 | Panel title |
| Body | 13px | 500 | 1.35 | 0 | Standard macOS labels |
| Body/sm | 12px | 500 | 1.3 | 0 | Popover rows |
| Caption | 11px | 550 | 1.25 | 0 | Metric labels |
| Mono/Data | 12px | 600 | 1.25 | 0 | Numbers and rates |

### Font Stack

- Primary: system macOS stack, SF Pro Text/Display through SwiftUI defaults.
- Mono: system monospaced digits via `.monospacedDigit()`.

### Rules

- Metrics use tabular digits.
- Keep popover text compact but never below 11px.
- Do not use hero-scale type inside compact panels.

## 4. Spacing & Layout

### Base Unit

All spacing derives from 4px.

| Token | Value | Usage |
| --- | --- | --- |
| `space1` | 4px | Tight icon/text gaps |
| `space2` | 8px | Row gaps, chips |
| `space3` | 12px | Compact panel padding |
| `space4` | 16px | Standard panel padding |
| `space5` | 20px | Dashboard section gaps |
| `space6` | 24px | Window outer padding |

### Grid

- Popover width: 340px, fixed content rhythm.
- Dashboard minimum: 860px by 640px, scrolling content.
- Metric rows use stable columns and fixed-height chips to prevent jitter.

### Rules

- Prefer one major value per tile.
- Secondary values live as captions, not competing large text.
- Preserve the current account list density because it is already readable.

## 5. Components

### Status pill
- Structure: label/value pair in a capsule.
- Variants: neutral, success, warning, error, info.
- States: default, hover for buttons, disabled for unavailable actions.
- Accessibility: text label must communicate the state without relying on color.
- Motion: opacity/scale only.

### Metric tile
- Structure: label, large tabular value, optional subtitle, progress bar.
- Variants: CPU, memory, spend, cache, connector.
- States: normal, warning, critical.
- Accessibility: visible label and numeric value.
- Motion: progress width changes can animate only through transform/opacity when needed.
- Swap is a system pressure metric, not a connector state. Label it as `메모리 스왑`, never just `스왑`, so users do not confuse it with network or provider connection status.

### Popover panel
- Structure: translucent tonal group with compact title and rows.
- Variants: system, totals, accounts, power.
- States: normal, loading, empty.
- Accessibility: no icon-only command without tooltip/help.

### Dashboard panel
- Structure: rounded tonal section with title, action slot, content.
- Variants: hero, connector, chart, settings, account.
- States: normal, empty, loading.
- Accessibility: buttons use native controls and focus rings.

### Hero status band
- Structure: mascot, headline status, compact activity facts, system chips.
- Variants: active, idle, pressure.
- States: normal, loading.
- Accessibility: headline states the activity level in text; chips include labels and values.
- Motion: mascot may animate through the menu bar icon, not inside the dashboard unless a future reduced-motion path exists.

### Connector strip
- Structure: one primary readiness value plus compact semantic chips.
- Variants: ready, partial, disconnected.
- States: default, refresh pending, empty.
- Accessibility: chip text includes the provider type and count.
- Motion: none required.

## 6. Motion & Interaction

| Type | Duration | Easing | Usage |
| --- | --- | --- | --- |
| Micro | 120ms | ease-out | Button press, chip hover |
| Standard | 220ms | ease-in-out | Panel state changes |
| Mascot | timer driven | linear frame switch | Running icon |

### Rules

- Menu bar mascot motion is allowed; popover position stays fixed.
- Do not animate layout properties.
- Respect reduced motion if broader animation is added later.

## 7. Depth & Surface

### Strategy

Mixed tonal shift and light borders. Popover uses material translucency; dashboard uses warm native surfaces.

| Level | Treatment | Usage |
| --- | --- | --- |
| Level 0 | `surfacePrimary` | Window and popover base |
| Level 1 | `surfaceSecondary` tonal block | Group sections |
| Level 2 | `surfaceElevated` + subtle border | Cards, rows, buttons |
| Level 3 | Accent tint + border | Selected/active state |

### Rules

- Avoid card-in-card stacking.
- Use depth only to clarify grouping.
- Rounded radius: 8px for cards/panels, capsule only for small status pills.
