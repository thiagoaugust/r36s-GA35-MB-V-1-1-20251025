#!/usr/bin/env bash
# fetch-freeware.sh — Baixa jogos gratuitos/shareware (Content Downloader oficial da libretro)
# e monta em work/freeware/ a mesma estrutura da p1 (/storage/roms). O 03-build.sh copia
# work/freeware/ para a p1 quando a pasta existe.
#
# Só entram jogos com núcleo 32 bits presente no SYSTEM (ver CLAUDE.md). Não precisa de sudo.
#
# Uso (WSL, na raiz do repositório):
#   bash scripts/fetch-freeware.sh

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DL="$REPO_DIR/work/downloads"
FW="$REPO_DIR/work/freeware"
BASE="https://buildbot.libretro.com/assets/cores"
for c in curl unzip sha256sum; do command -v "$c" >/dev/null || { echo "Falta '$c' (sudo apt install -y curl unzip)" >&2; exit 1; }; done
mkdir -p "$DL"
rm -rf "$FW"; mkdir -p "$FW/ports"

# baixa <caminho no buildbot> <sha256>, confere e extrai em $TMPX
fetch() {
  local url="$BASE/$1" sha="$2" f="$DL/$(basename "$1")"
  [[ -f "$f" ]] || { echo "  baixando $(basename "$1")"; curl -sfL --retry 3 -o "$f" "$url"; }
  echo "$sha  $f" | sha256sum -c --quiet - || { echo "SHA-256 não confere: $f (apague e rode de novo)" >&2; exit 1; }
  TMPX="$(mktemp -d)"; unzip -q "$f" -d "$TMPX"
}
# gamelist.xml com nome amigável para <pasta> <caminho relativo do jogo> <nome>
gamelist() {
  printf '<?xml version="1.0"?>\n<gameList>\n\t<game>\n\t\t<path>./%s</path>\n\t\t<name>%s</name>\n\t</game>\n</gameList>\n' "$2" "$3" > "$1/gamelist.xml"
}

echo ">>> Doom (Shareware) → ports/doom (menu Doom / prboom)"
fetch "DOOM/Doom%20%28Shareware%29.zip" fc457ee786736dbc05a4a721fce0801507fc313748e091127cd9e04343930f3a
mkdir -p "$FW/ports/doom"; cp "$TMPX"/Doom/*.wad "$FW/ports/doom/"; rm -rf "$TMPX"
gamelist "$FW/ports/doom" doom1.wad "Doom (Shareware)"

echo ">>> Quake (Shareware) → ports/quake/id1 (tyrquake)"
fetch "Quake/Quake%20%28Shareware%29.zip" 54b818ad098f7242805a5585cbbfc897124f606e482ce7654707a04a42d6a701
mkdir -p "$FW/ports/quake/id1"; cp "$TMPX/Quake/PAK0.PAK" "$FW/ports/quake/id1/pak0.pak"; rm -rf "$TMPX"
gamelist "$FW/ports/quake" id1/pak0.pak "Quake (Shareware)"

echo ">>> Cave Story → ports/CaveStory (nxengine)"
fetch "Cave%20Story/Cave%20Story%20%28En%29.zip" b8e1b4ed667a6b075811abc52e468ef3c534e7e24e2ef0bc44d8ff95999c83fd
mkdir -p "$FW/ports/CaveStory"; cp -r "$TMPX/Cave Story (en)"/{Doukutsu.exe,Config.dat,data} "$FW/ports/CaveStory/"; rm -rf "$TMPX"
gamelist "$FW/ports/CaveStory" Doukutsu.exe "Cave Story"

echo ">>> Dinothawr → ports/dinothawr"
fetch "Dinothawr/Dinothawr.zip" 3672baf7aaaab8eb266887792ef7d84d3bcb9d9abe836653e3c232012d3ec43a
cp -r "$TMPX/dinothawr" "$FW/ports/"; rm -rf "$TMPX"
gamelist "$FW/ports/dinothawr" dinothawr.game "Dinothawr"

echo ">>> Rick Dangerous → ports/xrick"
fetch "Rick%20Dangerous/Rick%20Dangerous.zip" 9b65fd91a6a9cf06d67ce17999484c3e8d12c2d45ca5eb48923370baee150dd3
mkdir -p "$FW/ports/xrick"; cp "$TMPX/Rick Dangerous/data.zip" "$FW/ports/xrick/"; rm -rf "$TMPX"
gamelist "$FW/ports/xrick" data.zip "Rick Dangerous"

echo ">>> Wolfenstein 3D (Shareware) → ports/ecwolf (menu Wolfenstein 3D)"
fetch "Wolfenstein%203D/Wolfenstein%203D%20v1.4%20%28Shareware%29.zip" ff3a9389adae12aae7571a1752ebdcf1d12c9a586e084887f571bb0e36a522c5
# O ecwolf.sh do EmuELEC roda os dados de /emuelec/configs/ecwolf; um arquivo .ecwolf
# com SUBDIR/PARAMS aponta para outra pasta e escolhe os dados .wl1 do shareware.
mkdir -p "$FW/ports/ecwolf/wolf3d-shareware" "$FW/ports/ecwolf/games"
cp "$TMPX/Wolfenstein 3D v1.4 (Shareware)"/*.WL1 "$FW/ports/ecwolf/wolf3d-shareware/"; rm -rf "$TMPX"
printf 'SUBDIR=wolf3d-shareware\nPARAMS=--data wl1\n' > "$FW/ports/ecwolf/games/wolf3d-shareware.ecwolf"
gamelist "$FW/ports/ecwolf/games" wolf3d-shareware.ecwolf "Wolfenstein 3D (Shareware)"

echo
du -sh "$FW"
echo "Pronto. Rode o 03-build.sh: ele copia work/freeware/ para a p1."
