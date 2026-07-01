# Prism Launcher Import

## Detection

Default scan locations (also user-pickable + drag-and-drop of an instance folder):

- `~/Library/Application Support/PrismLauncher/instances/`
- `~/Library/Application Support/PolyMC/instances/` (legacy)

A folder is a Prism instance when it contains `instance.cfg` **and**
(`mmc-pack.json` or `.minecraft/`).

## Mapping

| Prism source | MetalCraft target |
|--------------|-------------------|
| `instance.cfg` `name` | instance name |
| `instance.cfg` `iconKey` | icon (mapped to built-in set, else copied) |
| `instance.cfg` `JavaPath`, `MaxMemAlloc`, `MinMemAlloc`, `JvmArgs` | java.path, memory, jvmArgs |
| `instance.cfg` `notes` | notes |
| `mmc-pack.json` components: `net.minecraft` | minecraftVersion |
| components: `net.fabricmc.fabric-loader` | loader = fabric + version |
| components: `org.quiltmc.quilt-loader` | loader = quilt + version |
| components: `net.minecraftforge` | loader = forge + version |
| components: `net.neoforged` | loader = neoforge + version |
| `.minecraft/` (mods, config, saves, resourcepacks, shaderpacks, screenshots, servers.dat, options.txt) | copied into new instance `.minecraft/` |

## Process

1. Parse + validate; show a preview card (name, version, loader, mod count, size).
2. Copy content with progress (APFS clonefile via `FileManager.copyItem` keeps this
   fast and cheap on the same volume).
3. Create `instance.json` with `importedFrom: { launcher: "prism", path, date }`.
4. Run the normal file-verification pass so missing libraries/assets download on
   first launch (Prism's shared library store is not copied — we use our own).
5. Instance is fully editable afterwards; the original Prism instance is never
   modified or deleted.

Unsupported components (e.g. jar mods) are listed in the import summary as skipped,
with the reason.
