# UI Design

**Design language:** native macOS, dark-mode-first, glassy and minimal, with subtle
Minecraft block/pixel accents. SF Pro / SF Rounded for numerals. 12pt-radius cards,
`.ultraThinMaterial` panels, spring animations (`.spring(response: 0.35)`), and an
accent color extracted from the selected instance icon or player skin.

## Window layout

```
┌────────────┬──────────────────────────────────────────────┐
│  ◉ ◉ ◉     │                                              │
│            │                 Content area                 │
│  ▶ Home    │                                              │
│  ▦ Instances                                              │
│  ⌘ Mods    │                                              │
│  ✦ Skins   │                                              │
│  ⌁ Servers │                                              │
│  ⚡ Optimize│                                              │
│  ≣ Logs    │                                              │
│  ⚙ Settings│                                              │
│            │                                              │
│  [avatar]  │                                              │
└────────────┴──────────────────────────────────────────────┘
   glassy sidebar (ultraThinMaterial, full-height, inset window style)
```

## Screens

### Login
Centered card on a blurred hero render. "Sign in with Microsoft" (the only option),
device-code sheet showing the 8-char code in large SF Mono with a "Copy & Open
Browser" button and an animated progress ring while polling. Legal footnote:
"Official Microsoft sign-in only. Your password never touches this app."

### Home dashboard
- **Hero row**: giant rounded **Play** button (accent gradient, subtle inner glow,
  `⌘↩` to launch) beside the selected instance card (icon, name, version, loader).
- **Status strip**: four `StatBadge` chips — Renderer (e.g. "Apple Silicon Max FPS"),
  Java ("Temurin 21 · aarch64 ✓"), FPS Optimization ("Optimized · +38% measured"),
  Account (avatar + name).
- **Grid below**: Recent instances (cards with pixel-art icons), News/patch notes
  (Mojang feed), Server shortcuts (online dot, player count), Crash alerts card
  (only when present, amber, links to diagnosis).
- Footer quick-buttons: Mods · Skins · Servers · Settings · Logs.

### Instances
Grid of beautiful cards: large icon tile with soft shadow, name, version + loader
chip, last played, kebab menu (Launch, Edit, Folder in Finder, Duplicate, Repair,
Export, Delete). `⌘N` new instance; drag-and-drop `.mrpack`/Prism folder anywhere.
Detail view = compact inspector with tabs: Overview · Mods · Shaders · Resource
Packs · Saves · Screenshots · Logs · Settings (Java/RAM/JVM/resolution/renderer).

### FPS Optimization Center
Left: preset cards (Balanced, Max FPS, Low-End, Shader-Friendly, Safe) with a
recommendation badge on the hardware-suggested one. Right: live stats panel (CPU,
GPU, memory, frame-time sparkline), RAM slider with a memory-pressure hint, JVM args
editor (chips + free field), renderer picker (unavailable modes shown greyed with the
reason), and a **Benchmark** button → before/after comparison bars with measured
FPS / 1% lows.

### Experimental Metal Renderer enable-sheet
⚠️ badge, plain-language explanation of what is and isn't Metal-rendered, crash
behavior ("after 2 crashes it turns itself off"), buttons: **Enable Experimental
Renderer** / **Launch with OpenGL instead** / Cancel.

### Skins
3D rotating player model (SceneKit) + 2D texture view, slim/classic toggle, local
library grid, Upload (validates 64×64 or 64×32, PNG), Apply (official API), cape
shown when owned.

### Servers
Table with folders in a source list; columns: status dot, icon, name, MOTD
(formatted), players, ping. Row actions: Launch & Join, Copy Address, Edit.
Auto-ping on view; manual refresh `⌘R`.

### Logs
Segmented filter: Launcher · Game · Renderer · Crashes. Live tail with colorized
levels, search, "Reveal in Finder", crash diagnoses rendered as cards on top of the
raw report.

## Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘↩` | Launch selected instance |
| `⌘N` | New instance |
| `⌘1…7` | Sidebar sections |
| `⌘F` | Search in current view |
| `⌘R` | Refresh (pings, manifests, Modrinth) |
| `⌘,` | Settings |
| `⌘L` | Jump to live log while running |

## Motion & polish

- View transitions: `.transition(.opacity.combined(with: .move(edge:)))`, never hard
  cuts; loading screens use a shimmering block-grid placeholder, not spinners.
- The Play button morphs into a progress capsule during download/prepare, then into
  "Running" with a live memory sparkline.
- Native notifications: "Ready to play", "Crash detected — diagnosis ready",
  "Modpack update available". Finder integration: every entity has "Reveal in
  Finder"; drag-out of instance cards exports an archive.
