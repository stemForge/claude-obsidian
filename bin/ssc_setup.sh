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

# Hilfsfunktion: Config-Datei aus String schreiben, --force berücksichtigen
# Usage: write_config "$OBSIDIAN/app.json" <<'EOF' ... EOF
write_config() {
  local dst="$1"
  local content
  content=$(cat)
  if [ -f "$dst" ] && ! $FORCE; then
    echo "   ↷ $(basename "$dst") (bereits vorhanden, übersprungen)"
    return
  fi
  printf '%s\n' "$content" > "$dst"
  echo "   ✓ $(basename "$dst")"
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

# ── 3b. Transport erkennen ────────────────────────────────────────────────────
mkdir -p "$VAULT/.vault-meta"
bash "$VAULT/scripts/detect-transport.sh" --quiet 2>/dev/null \
  && echo "   ✓ .vault-meta/transport.json" \
  || echo "   ↷ transport.json (detect-transport fehlgeschlagen — filesystem als Fallback)"

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

write_config "$OBSIDIAN/graph.json" << EOF
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

# ── 6. app.json (excluded files) ─────────────────────────────────────────────
echo ""
echo "⚙️  Obsidian-Config..."
write_config "$OBSIDIAN/app.json" << 'EOF'
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

# ── 7. appearance.json (CSS snippets aktivieren) ──────────────────────────────
write_config "$OBSIDIAN/appearance.json" << 'EOF'
{
  "enabledCssSnippets": [
    "vault-colors",
    "ITS-Dataview-Cards",
    "ITS-Image-Adjustments"
  ]
}
EOF

# ── 8. .gitignore ─────────────────────────────────────────────────────────────
write_config "$VAULT/.gitignore" << 'EOF'
# Obsidian runtime state
.obsidian/workspace.json
.obsidian/workspace-mobile.json
.obsidian/workspace-visual.json
.obsidian/plugins/*/data.json
!.obsidian/plugins/calendar/data.json
!.obsidian/plugins/thino/data.json
.obsidian/plugins/obsidian-excalidraw-plugin/main.js

# Large assets (uncomment to exclude images from git)
# _attachments/images/
.smart-connections/
.obsidian-git-data
.trash/

# System
.DS_Store
Thumbs.db

# Python
__pycache__/
*.pyc
.venv/

# Node
node_modules/

# Secrets
.env
.env.local
*.local.md
*.pem
*.key
*.p12
*.pfx
id_rsa*
id_ed25519*
credentials*
secrets.y*ml
auth.json

# Obsidian auto-created files
WIKI*.md
PROMPT.md
Welcome.md
*.tmp.*
????-??-??.md

# Video and large media
*.mkv
*.mp4
*.mov
*.avi

# Transcripts (copyright)
*Transcript*.txt

# DragonScale runtime (lockfiles, caches — regenerable)
.vault-meta/.address.lock
.vault-meta/.tiling.lock
.vault-meta/tiling-cache.json
.vault-meta/tiling-cache.*.tmp
.vault-meta/.wiki-lock.meta
.vault-meta/.bm25.lock
.vault-meta/.embed-cache.lock
.vault-meta/locks/*
!.vault-meta/locks/.gitkeep
.vault-meta/chunks/
.vault-meta/bm25/
.vault-meta/embed-cache.json
.vault-meta/embed-cache.*.tmp
.vault-meta/transport.json
.vault-meta/transport.*.tmp
.vault-meta/hook.log
.vault-meta/mode.json
.vault-meta/mode.*.tmp
EOF

# ── 9. Plugins ────────────────────────────────────────────────────────────────
echo ""
echo "🔌 Plugins..."

# Obsidian-Version ermitteln (für Kompatibilitätsprüfung)
get_obsidian_version() {
  local plist="/Applications/Obsidian.app/Contents/Info.plist"
  [ -f "$plist" ] && /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist" 2>/dev/null || echo ""
}

version_gte() {
  [ "$(printf '%s\n%s' "$1" "$2" | sort -V | head -1)" = "$2" ]
}

# Letzten kompatiblen Release-Tag über GitHub API suchen
find_compatible_tag() {
  local repo="$1" obsidian_version="$2"
  python3 - <<PYEOF
import urllib.request, json, sys
repo = "$repo"
obsidian = "$obsidian_version"
def ver_tuple(v):
    try: return tuple(int(x) for x in str(v).split('.'))
    except: return (0, 0, 0)
obsidian_t = ver_tuple(obsidian)
url = "https://api.github.com/repos/{}/releases?per_page=20".format(repo)
try:
    req = urllib.request.Request(url, headers={"User-Agent": "ssc-vault-setup"})
    with urllib.request.urlopen(req, timeout=15) as r:
        releases = json.loads(r.read())
except Exception: sys.exit(0)
for release in releases:
    tag = release.get("tag_name", "")
    for asset in release.get("assets", []):
        if asset["name"] == "manifest.json":
            try:
                req2 = urllib.request.Request(asset["browser_download_url"], headers={"User-Agent": "ssc-vault-setup"})
                with urllib.request.urlopen(req2, timeout=10) as r:
                    manifest = json.loads(r.read())
                if obsidian_t >= ver_tuple(manifest.get("minAppVersion", "0.0.0")):
                    print(tag); sys.exit(0)
            except Exception: pass
PYEOF
}

# Plugin aus Fork kopieren (manifest.json + main.js + styles.css, ohne data.json)
copy_plugin() {
  local id="$1"
  local src="$FORK_ROOT/.obsidian/plugins/$id"
  local dst="$OBSIDIAN/plugins/$id"
  if [ -f "$dst/main.js" ] && ! $FORCE; then
    echo "   ↷ $id (bereits vorhanden, übersprungen)"
    return
  fi
  mkdir -p "$dst"
  for f in main.js manifest.json styles.css; do
    [ -f "$src/$f" ] && cp "$src/$f" "$dst/$f" || true
  done
  echo "   ✓ $id (aus Fork kopiert)"
}

# Plugin von GitHub herunterladen (mit Versionscheck)
OBSIDIAN_VERSION=$(get_obsidian_version)
download_plugin() {
  local id="$1" repo="$2"
  local dst="$OBSIDIAN/plugins/$id"
  if [ -f "$dst/main.js" ] && ! $FORCE; then
    echo "   ↷ $id (bereits vorhanden, übersprungen)"
    return
  fi
  mkdir -p "$dst"
  local base="https://github.com/$repo/releases/latest/download"
  if [ -n "$OBSIDIAN_VERSION" ]; then
    local manifest_json min_ver
    manifest_json=$(curl -fsSL "$base/manifest.json" 2>/dev/null || echo "")
    if [ -n "$manifest_json" ]; then
      min_ver=$(echo "$manifest_json" | python3 -c \
        "import sys,json; print(json.load(sys.stdin).get('minAppVersion','0.0.0'))" 2>/dev/null || echo "0.0.0")
      if ! version_gte "$OBSIDIAN_VERSION" "$min_ver"; then
        echo "   ⚠  $id: neueste Version erfordert Obsidian >= $min_ver — suche ältere Version..."
        local tag
        tag=$(find_compatible_tag "$repo" "$OBSIDIAN_VERSION")
        if [ -n "$tag" ]; then
          echo "   → $tag wird verwendet"
          base="https://github.com/$repo/releases/download/$tag"
        else
          echo "   ✗ $id: keine kompatible Version gefunden — übersprungen"
          rm -rf "$dst"; return
        fi
      fi
    fi
  fi
  echo "   ⬇  $id ..."
  curl -fsSL "$base/main.js"       -o "$dst/main.js"
  curl -fsSL "$base/manifest.json" -o "$dst/manifest.json"
  curl -fsSL "$base/styles.css"    -o "$dst/styles.css" 2>/dev/null || rm -f "$dst/styles.css"
  echo "   ✓ $id"
}

# Plugins aus Fork kopieren (main.js committed)
copy_plugin "calendar"
copy_plugin "obsidian-banners"
copy_plugin "thino"

# Plugins herunterladen
download_plugin "obsidian-git"        "vinzent03/obsidian-git"
download_plugin "realclaudian"        "yishentu/claudian"
download_plugin "obsidian-excalidraw-plugin" "zsviczian/obsidian-excalidraw-plugin"
download_plugin "dataview"            "blacksmithgu/obsidian-dataview"
download_plugin "templater-obsidian"  "silentvoid13/Templater"

# community-plugins.json schreiben (alle 8 IDs)
write_config "$OBSIDIAN/community-plugins.json" << 'EOF'
[
  "dataview",
  "templater-obsidian",
  "obsidian-git",
  "realclaudian",
  "obsidian-excalidraw-plugin",
  "obsidian-banners",
  "calendar",
  "thino"
]
EOF

echo ""
echo "════════════════════════════════════════"
echo "✅  Vault eingerichtet: $VAULT"
echo "════════════════════════════════════════"
echo ""
echo "Nächste Schritte:"
echo ""
echo "  1. Obsidian öffnen"
echo "     Manage Vaults → Open folder as vault → $VAULT"
echo ""
echo "  2. Community Plugins aktivieren"
echo "     Settings → Community Plugins → Enable (einmalig bestätigen)"
echo "     Installierte Plugins:"
echo "       - Dataview          (Abfragen und Tabellen aus Notiz-Metadaten)"
echo "       - Templater         (Vorlagen mit Skript-Unterstützung)"
echo "       - Obsidian Git      (automatische Git-Commits)"
echo "       - Claudian          (Claude Code Integration)"
echo "       - Excalidraw        (Freihand-Zeichnungen und Annotationen)"
echo "       - Banners           (Header-Bilder per Frontmatter)"
echo "       - Calendar          (Sidebar-Kalender mit Wordcount)"
echo "       - Thino             (Schnell-Notizen)"
echo ""
echo "  3. Wiki aufsetzen"
echo "     Claude Code öffnen (im Vault-Verzeichnis) → /wiki"
echo ""
echo "CSS Snippets aktiv:"
echo "  - vault-colors:          Ordner in wiki/ farblich hervorgehoben"
echo "  - ITS-Dataview-Cards:    Dataview-Karten mit .cards Klasse"
echo "  - ITS-Image-Adjustments: Bildgröße per |100 im Embed-Link"
echo ""
echo "Graph: path:wiki gefiltert, Ordner farblich nach Mode ($MODE) kodiert."
echo ""
echo "Visuelles Layout (Canvas + Calendar + Thino Sidebar):"
echo "  Obsidian schließen, dann:"
echo "    cp $OBSIDIAN/workspace-visual.json $OBSIDIAN/workspace.json"
echo "  Obsidian neu öffnen."
echo ""
echo "Mode: $MODE"
echo "Transport: $(python3 -c "import json; t=json.load(open('$VAULT/.vault-meta/transport.json')); print(t.get('preferred','filesystem'))" 2>/dev/null || echo "filesystem")"
echo ""
echo "Weitere Optionen:"
echo "  bash bin/setup-dragonscale.sh   # Adress-System + semantische Duplikaterkennung"
echo "  bash bin/setup-mode.sh          # Methodology-Mode wechseln"
echo "  bash bin/setup-retrieve.sh      # Hybrid-Retrieval (BM25 + Embeddings)"
