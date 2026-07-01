# Modrinth Integration

REST client for `https://api.modrinth.com/v2` with a descriptive `User-Agent`
(`metalcraft-launcher/<version> (contact url)`) as Modrinth's API rules require.

## Search & browse

- `GET /search` with `facets` for project type (`modpack` / `mod` / `shader` /
  `resourcepack`), loader, MC version, and category; queries are debounced 300ms.
- Detail view: `GET /project/{id}` (+ `/version`, `/team` for authors) — shows title,
  description (rendered Markdown), author, downloads, gallery screenshots, supported
  MC versions, loaders, **license, and source link** (safety requirement).

## Modpack install (`.mrpack`)

1. Pick version (`GET /project/{id}/version`, filtered to selected MC version/loader).
2. Download the `.mrpack` (it is a zip):
   - `modrinth.index.json` — `files[]` with `path`, `hashes.sha1/sha512`,
     `downloads[]`, `env` (client/server support)
   - `overrides/` (+ `client-overrides/`) — copied into the instance game dir
3. Create instance from `dependencies` (`minecraft`, `fabric-loader`, `quilt-loader`,
   `forge`, `neoforge`).
4. Download every file to its `path`, verifying sha512 (fall back sha1); reject any
   path escaping the instance dir (zip-slip guard).
5. Record `{ projectId, versionId }` in `instance.json` for updates.

## Updates

- For instances with a Modrinth link: compare installed `versionId` against the
  newest compatible version; show an Update badge.
- Update = install new index into a staging dir, diff against old index (files owned
  by the pack are replaced/removed; user-added files untouched), then atomically swap.

## Dependency resolution (mods)

When installing a single mod: read the version's `dependencies[]`
(`required` / `optional` / `incompatible`). Required deps resolve recursively
(cycle-safe, deduped by project id); incompatible mods present in the instance
produce a warning card before install.

## Drag-and-drop

`.mrpack` dropped anywhere on the window → import sheet (same pipeline from step 2,
metadata read from the embedded index).
