#!/usr/bin/env bash
# ssc_setup.sh — Neuen Obsidian-Vault anlegen (eigenständig, vollständig konfiguriert)
# Usage: bash bin/ssc_setup.sh /pfad/zum/neuen/vault [--mode MODE] [--git] [--force]
# --mode MODE: generic | lyt | para | zettelkasten (sonst interaktiv)
# --git:       git init + erster Commit nach dem Setup
# --force:     vorhandene Dateien überschreiben (Standard: überspringen)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORK_ROOT="$(dirname "$SCRIPT_DIR")"

if [ -z "${1:-}" ]; then
  echo "Fehler: Kein Zielverzeichnis angegeben."
  echo "Usage: bash bin/ssc_setup.sh /pfad/zum/neuen/vault [--git] [--force]"
  exit 1
fi

GIT_INIT=false
FORCE=false
MODE_ARG=""
args=("$@")
i=0
while [ $i -lt ${#args[@]} ]; do
  case "${args[$i]}" in
    --git)   GIT_INIT=true ;;
    --force) FORCE=true ;;
    --mode)  i=$((i+1)); MODE_ARG="${args[$i]:-}" ;;
  esac
  i=$((i+1))
done

# Pfad normalisieren (funktioniert auch wenn Verzeichnis noch nicht existiert)
VAULT="$(cd "$(dirname "$1")" 2>/dev/null && pwd)/$(basename "$1")"
OBSIDIAN="$VAULT/.obsidian"

echo "🗂  Vault wird eingerichtet: $VAULT"
$FORCE && echo "   ⚠  --force aktiv: vorhandene Dateien werden überschrieben"

# Hilfsfunktion: Datei kopieren, je nach --force überspringen oder überschreiben
# Gibt 0 zurück wenn kopiert, 1 wenn übersprungen
copy_file() {
  local src="$1" dst="$2"
  if [ -f "$dst" ] && ! $FORCE; then
    echo "   ↷ $(basename "$dst") (bereits vorhanden, übersprungen)"
    return 1
  fi
  cp "$src" "$dst"
  return 0
}

# ── 1. Verzeichnisstruktur anlegen ────────────────────────────────────────────
echo ""
echo "📁 Verzeichnisse..."
mkdir -p "$OBSIDIAN/plugins"
mkdir -p "$OBSIDIAN/snippets"
mkdir -p "$VAULT/.raw"
mkdir -p "$VAULT/_templates"
mkdir -p "$VAULT/bin"
mkdir -p "$VAULT/scripts"

# ── 2. Snippets kopieren ──────────────────────────────────────────────────────
echo "🎨 Snippets..."
for f in "$FORK_ROOT/.obsidian/snippets/"*.css; do
  [ -f "$f" ] || continue
  copy_file "$f" "$OBSIDIAN/snippets/$(basename "$f")" && echo "   ✓ $(basename "$f")" || true
done

# ── 3. bin/ und scripts/ kopieren ─────────────────────────────────────────────
echo "📜 Scripts..."
for f in "$FORK_ROOT/bin/"*.sh; do
  [ -f "$f" ] || continue
  copy_file "$f" "$VAULT/bin/$(basename "$f")" && echo "   ✓ bin/$(basename "$f")" || true
done
for f in "$FORK_ROOT/scripts/"*; do
  [ -f "$f" ] || continue
  copy_file "$f" "$VAULT/scripts/$(basename "$f")" && echo "   ✓ scripts/$(basename "$f")" || true
done
chmod +x "$VAULT/bin/"*.sh 2>/dev/null || true
chmod +x "$VAULT/scripts/"*.sh 2>/dev/null || true

# ── 4. Methodology mode wählen + wiki-Ordner anlegen ──────────────────────────
echo ""
echo "🗂  Methodology mode..."
if [ -n "$MODE_ARG" ]; then
  bash "$VAULT/bin/setup-mode.sh" --mode "$MODE_ARG"
else
  bash "$VAULT/bin/setup-mode.sh"
fi
MODE=$(python3 "$VAULT/scripts/wiki-mode.py" get 2>/dev/null || echo "generic")

# ── 5. graph.json schreiben (mode-abhängige colorGroups) ──────────────────────
echo ""
echo "📊 graph.json ($MODE)..."
case "$MODE" in
  para)
    COLOR_GROUPS='[
    { "query": "path:wiki/projects",  "color": { "a": 1, "rgb": 12945088 } },
    { "query": "path:wiki/areas",     "color": { "a": 1, "rgb": 5227007  } },
    { "query": "path:wiki/resources", "color": { "a": 1, "rgb": 6986069  } },
    { "query": "path:wiki/archives",  "color": { "a": 1, "rgb": 8947848  } },
    { "query": "path:wiki",           "color": { "a": 1, "rgb": 5676246  } }
  ]' ;;
  lyt)
    COLOR_GROUPS='[
    { "query": "path:wiki/mocs",      "color": { "a": 1, "rgb": 12945088 } },
    { "query": "path:wiki/notes",     "color": { "a": 1, "rgb": 5227007  } },
    { "query": "path:wiki",           "color": { "a": 1, "rgb": 5676246  } }
  ]' ;;
  zettelkasten)
    COLOR_GROUPS='[
    { "query": "path:wiki",           "color": { "a": 1, "rgb": 5676246  } }
  ]' ;;
  *)  # generic
    COLOR_GROUPS='[
    { "query": "path:wiki/entities",  "color": { "a": 1, "rgb": 12945088 } },
    { "query": "path:wiki/concepts",  "color": { "a": 1, "rgb": 5227007  } },
    { "query": "path:wiki/sources",   "color": { "a": 1, "rgb": 6986069  } },
    { "query": "path:wiki/meta",      "color": { "a": 1, "rgb": 5676246  } },
    { "query": "path:wiki",           "color": { "a": 1, "rgb": 5676246  } }
  ]' ;;
esac

cat > "$OBSIDIAN/graph.json" << EOF
{
  "collapse-filter": false,
  "search": "path:wiki",
  "showTags": false,
  "showAttachments": false,
  "hideUnresolved": true,
  "showOrphans": false,
  "collapse-color-groups": false,
  "colorGroups": $COLOR_GROUPS,
  "showArrow": true,
  "textFadeMultiplier": -1,
  "nodeSizeMultiplier": 1.8,
  "lineSizeMultiplier": 1.2,
  "centerStrength": 0.5,
  "repelStrength": 30,
  "linkStrength": 1.5,
  "linkDistance": 120,
  "scale": 1.0
}
EOF

# ── 3. Write app.json (excluded files) ───────────────────────────────────────
cat > "$OBSIDIAN/app.json" << 'EOF'
{
  "userIgnoreFilters": [
    "agents/",
    "commands/",
    "hooks/",
    "skills/",
    "_templates/",
    "README.md",
    "CLAUDE.md",
    "WIKI.md",
    "Welcome.md"
  ]
}
EOF

# ── 4. Write appearance.json (enable CSS snippets) ───────────────────────────
cat > "$OBSIDIAN/appearance.json" << 'EOF'
{
  "enabledCssSnippets": [
    "vault-colors",
    "ITS-Dataview-Cards",
    "ITS-Image-Adjustments"
  ]
}
EOF

# ── 5. Download Excalidraw main.js (8MB, not in git) ─────────────────────────
EXCALIDRAW="$OBSIDIAN/plugins/obsidian-excalidraw-plugin"
if [ -f "$EXCALIDRAW/manifest.json" ] && [ ! -f "$EXCALIDRAW/main.js" ]; then
  echo "Downloading Excalidraw main.js (~8MB)..."
  curl -sS -L \
    "https://github.com/zsviczian/obsidian-excalidraw-plugin/releases/latest/download/main.js" \
    -o "$EXCALIDRAW/main.js"
  echo "✓ Excalidraw main.js downloaded"
elif [ -f "$EXCALIDRAW/main.js" ]; then
  echo "✓ Excalidraw main.js already present"
fi

echo ""
echo "✓ Setup complete."
echo ""
echo "Next steps:"
echo "  1. Open Obsidian"
echo "  2. Manage Vaults → Open folder as vault → select: $VAULT"
echo "  3. Enable community plugins when prompted (Calendar, Thino, Excalidraw, Banners are pre-installed)"
echo "  4. Install: Dataview, Templater, Obsidian Git  (Settings → Community Plugins)"
echo "  5. Type /wiki in Claude Code to scaffold your knowledge base"
echo ""
echo "Pre-installed plugins:"
echo "  - Calendar (sidebar calendar with word count + task dots)"
echo "  - Thino (quick memo capture)"
echo "  - Excalidraw (freehand drawing + image annotation)"
echo "  - Banners (add banner: to any note frontmatter for header images)"
echo ""
echo "CSS snippets enabled:"
echo "  - vault-colors: color-codes wiki/ folders in file explorer"
echo "  - ITS-Dataview-Cards: use \`\`\`dataviewjs with .cards for card grids"
echo "  - ITS-Image-Adjustments: append |100 to image embeds for sizing"
echo ""
echo "Views available:"
echo "  - Wiki Map canvas (wiki/Wiki Map.canvas) — knowledge graph"
echo "  - Design Ideas canvas (projects/visual-vault/design-ideas.canvas) — visual reference board"
echo "  - Graph view filtered to wiki/ only, color-coded by type"
echo ""
echo "To switch to the visual layout (Canvas + Calendar + Thino sidebar):"
echo "  Quit Obsidian, then run:"
echo "    cp $OBSIDIAN/workspace-visual.json $OBSIDIAN/workspace.json"
echo "  Then reopen Obsidian."
echo ""
echo "Graph colors: if they reset after closing Obsidian, open Graph settings"
echo "→ Color groups and re-add them once. They persist permanently after that."
