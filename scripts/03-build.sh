#!/usr/bin/env bash
# 03-build.sh — Gera uma imagem customizada a partir do dump ORIGINAL.
#
# O original nunca é alterado: o script copia a imagem para out/ e aplica,
# dentro da cópia, as customizações versionadas em custom/.
#
# Uso (WSL, na raiz do repositório):
#   sudo bash scripts/03-build.sh "SISTEMA R36S GA36-MB V1.2-20260416.img" [--out caminho.img] [--verify] [--roms pasta]
#
#   --out     caminho da imagem gerada (padrão: out/r36s-custom-<data>.img)
#   --verify  confere o SHA-256 do original com o registrado em docs/layout-imagem.md
#   --roms    pasta com subpastas por sistema; copia as listadas em custom/roms.list
#             para a p1, que é esticada (é a última partição) para caber tudo

set -euo pipefail

EXPECTED_SHA="550e071d117929ddc373572964bc544c18f03f510a06bda01832089e41eba9ad"
SRC="" ; OUT="" ; VERIFY=0 ; ROMS=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)    OUT="$2"; shift 2 ;;
    --verify) VERIFY=1; shift ;;
    --roms)   ROMS="$2"; shift 2 ;;
    *)        SRC="$1"; shift ;;
  esac
done

[[ -n "$SRC" ]] || { echo "uso: sudo $0 <imagem-original.img> [--out saida.img] [--verify] [--roms pasta]" >&2; exit 1; }
[[ $EUID -eq 0 ]] || { echo "Rode com sudo." >&2; exit 1; }
[[ -f "$SRC" ]]   || { echo "Imagem não encontrada: $SRC" >&2; exit 1; }
[[ -z "$ROMS" || -d "$ROMS" ]] || { echo "Pasta de ROMs não encontrada: $ROMS" >&2; exit 1; }
FREEWARE="$(cd "$(dirname "$0")/.." && pwd)/work/freeware"   # gerado por scripts/fetch-freeware.sh
[[ -n "$ROMS" || -d "$FREEWARE" ]] && NEED_VFAT="mkfs.vfat fsck.vfat" || NEED_VFAT=""
for c in partx losetup e2fsck $NEED_VFAT; do
  command -v "$c" >/dev/null || { echo "Comando '$c' não encontrado. Rode: sudo apt install -y util-linux e2fsprogs dosfstools" >&2; exit 1; }
done

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CUSTOM="$REPO_DIR/custom"
OUT="${OUT:-$REPO_DIR/out/r36s-custom-$(date +%Y%m%d-%H%M%S).img}"
MNT="$REPO_DIR/work/build-mnt"
mkdir -p "$(dirname "$OUT")" "$MNT"

L7="" ; LSYS="" ; L8="" ; L1="" ; L1S="" ; L2="" ; P2DIR=""
cleanup() {
  [[ -n "$P2DIR" ]] && rm -rf "$P2DIR" || true
  mountpoint -q "$MNT/p2" 2>/dev/null && umount "$MNT/p2" || true
  [[ -n "$L2" ]] && losetup -d "$L2" 2>/dev/null || true
  mountpoint -q "$MNT/p1" 2>/dev/null && umount "$MNT/p1" || true
  mountpoint -q "$MNT/p1src" 2>/dev/null && umount "$MNT/p1src" || true
  [[ -n "$L1" ]] && losetup -d "$L1" 2>/dev/null || true
  [[ -n "$L1S" ]] && losetup -d "$L1S" 2>/dev/null || true
  mountpoint -q "$MNT/system" 2>/dev/null && umount "$MNT/system" || true
  [[ -n "$LSYS" ]] && losetup -d "$LSYS" 2>/dev/null || true
  mountpoint -q "$MNT/p7" 2>/dev/null && umount "$MNT/p7" || true
  mountpoint -q "$MNT/p8" 2>/dev/null && umount "$MNT/p8" || true
  [[ -n "$L7" ]] && losetup -d "$L7" 2>/dev/null || true
  [[ -n "$L8" ]] && losetup -d "$L8" 2>/dev/null || true
  rmdir "$MNT"/* "$MNT" 2>/dev/null || true
}
trap cleanup EXIT

step() { printf '\n>>> %s\n' "$1"; }
warn() { printf '  [AVISO] %s\n' "$1"; }

# Anexa a partição N da imagem $1 como loop (opções extras em $3)
attach_part() {
  local img="$1" n="$2" ro="${3:-}"
  local start sectors
  read -r start sectors < <(partx -g -o START,SECTORS -n "$n" "$img")
  losetup --find --show $ro --offset $((start * 512)) --sizelimit $((sectors * 512)) "$img"
}

# Define chave=valor num arquivo estilo emuelec.conf (substitui ou adiciona)
set_kv() {
  local file="$1" key="$2" val="$3" tmp
  tmp="$(mktemp)"
  awk -v k="$key" -v v="$val" '
    index($0, k "=") == 1 { print k "=" v; done = 1; next }
    { print }
    END { if (!done) print k "=" v }' "$file" > "$tmp"
  cat "$tmp" > "$file"   # preserva dono/permissões do original
  rm -f "$tmp"
}

# Lê todos os custom/emuelec.conf.d/*.conf em ordem -> linhas "chave=valor"
collect_kv() {
  local f
  for f in "$CUSTOM"/emuelec.conf.d/*.conf; do
    [[ -f "$f" ]] || continue
    tr -d '\r' < "$f" | grep -Ev '^\s*(#|$)' | sed 's/^\s*//; s/\s*$//'
  done
}

# Conteúdo da p2 (logo de boot, telas de bateria): custom/overlay/p2/ + a imagem de custom/logo/,
# convertida para bootlogo.bmp. O bootloader só entende BMP 640x480 24 bits sem compressão.
P2DIR="$(mktemp -d)"
[[ -d "$CUSTOM/overlay/p2" ]] && cp -r "$CUSTOM/overlay/p2/." "$P2DIR"
mapfile -t LOGOS < <(find "$CUSTOM/logo" -maxdepth 1 -type f ! -name '.*' ! -iname '*.md' 2>/dev/null)
(( ${#LOGOS[@]} <= 1 )) || { echo "custom/logo/ deve ter só uma imagem (tem ${#LOGOS[@]})" >&2; exit 1; }
if (( ${#LOGOS[@]} )); then
  IM="$(command -v magick || command -v convert)" || { echo "ImageMagick não encontrado. Rode: sudo apt install -y imagemagick" >&2; exit 1; }
  # Encaixa em 640x480 sem distorcer (sobra fica preta); BMP3 = cabeçalho clássico de 54 bytes
  "$IM" "${LOGOS[0]}[0]" -auto-orient -resize 640x480 -background black -gravity center -extent 640x480 \
    -alpha off -type TrueColor BMP3:"$P2DIR/bootlogo.bmp"
fi
for f in $(cd "$P2DIR" && find . -iname '*.bmp'); do
  file "$P2DIR/$f" | grep -q '640 x 480 x 24' \
    || { echo "p2/$f não é BMP 640x480 24 bits: $(file -b "$P2DIR/$f")" >&2; exit 1; }
done

# ---------------------------------------------------------------------------
step "1/6 Verificando original"
echo "  Origem: $SRC"
if [[ $VERIFY -eq 1 ]]; then
  sha="$(sha256sum "$SRC" | cut -d' ' -f1)"
  if [[ "$sha" == "$EXPECTED_SHA" ]]; then echo "  SHA-256 confere."
  else warn "SHA-256 diferente do dump documentado ($sha). Continuando mesmo assim."; fi
fi
need=$(stat -c %s "$SRC")

# Conteúdo extra da p1: pares "origem|destino na p1" (ROMs de --roms + work/freeware/)
COPY=() ; ROM_BYTES=0
if [[ -n "$ROMS" ]]; then
  for s in $(tr -d '\r' < "$CUSTOM/roms.list" | grep -Ev '^\s*(#|$)'); do
    if [[ -d "$ROMS/$s" ]]; then COPY+=("$ROMS/$s|$s")
    else warn "pasta '$s' não existe em $ROMS — pulando"; fi
  done
fi
[[ -d "$FREEWARE" ]] && COPY+=("$FREEWARE|.")
# Soma o tamanho e calcula o novo tamanho da p1 (última partição)
if [[ ${#COPY[@]} -gt 0 ]]; then
  read -r P1_START P1_SECTORS < <(partx -g -o START,SECTORS -n 1 "$SRC")
  (( (P1_START + P1_SECTORS) * 512 == need )) || { echo "p1 não é a última partição da imagem — abortando" >&2; exit 1; }
  (( $(od -An -tu4 -j454 -N4 "$SRC") == P1_START )) || { echo "p1 não é a 1ª entrada da MBR — abortando" >&2; exit 1; }
  for c in "${COPY[@]}"; do
    b=$(du -sb "${c%%|*}" | cut -f1); ROM_BYTES=$((ROM_BYTES + b))
    echo "  p1/${c#*|}: $((b / 1048576)) MiB  (${c%%|*})"
  done
  # +10% de folga para clusters FAT32 com muitos arquivos pequenos, +64 MiB, arredondado para 1 MiB
  P1_NEW=$(( P1_SECTORS + ROM_BYTES / 512 * 11 / 10 + 131072 ))
  P1_NEW=$(( (P1_NEW + 2047) / 2048 * 2048 ))
  need=$(( (P1_START + P1_NEW) * 512 ))
  echo "  p1: $((P1_SECTORS / 2048)) MiB → $((P1_NEW / 2048)) MiB; imagem final: $((need / 1048576)) MiB"
fi
free=$(df -B1 --output=avail "$(dirname "$OUT")" | tail -n1)
(( free > need )) || { echo "Espaço insuficiente em $(dirname "$OUT")" >&2; exit 1; }

# ---------------------------------------------------------------------------
step "2/6 Validando customizações contra o SYSTEM (somente leitura)"
mapfile -t KV < <(collect_kv)
if [[ ${#KV[@]} -eq 0 ]]; then echo "  Nenhuma customização em custom/emuelec.conf.d/"; fi
for kv in "${KV[@]}"; do echo "  $kv"; done

L7="$(attach_part "$SRC" 7 --read-only)"
mkdir -p "$MNT/p7" "$MNT/system"
if mount -t vfat -o ro "$L7" "$MNT/p7" 2>/dev/null \
   && LSYS="$(losetup --find --show --read-only "$MNT/p7/SYSTEM")" \
   && mount -t squashfs -o ro "$LSYS" "$MNT/system" 2>/dev/null; then
  S="$MNT/system"
  for kv in "${KV[@]}"; do
    key="${kv%%=*}"; val="${kv#*=}"
    case "$key" in
      system.timezone)
        [[ -e "$S/usr/share/zoneinfo/$val" ]] && echo "  OK fuso '$val' existe no SYSTEM" \
          || warn "fuso '$val' NÃO encontrado em usr/share/zoneinfo do SYSTEM" ;;
      system.language)
        if [[ -e "$S/usr/config/emuelec/configs/locale/$val/LC_MESSAGES/emulationstation2.mo" ]]; then
          echo "  OK tradução '$val' encontrada no SYSTEM"
        else
          warn "tradução '$val' não encontrada no SYSTEM — a interface pode ficar em inglês"
        fi ;;
    esac
  done
else
  warn "não foi possível montar o SYSTEM para validação — pulando checagens"
fi
umount "$MNT/system" 2>/dev/null || true; [[ -n "$LSYS" ]] && losetup -d "$LSYS" || true; LSYS=""
umount "$MNT/p7" 2>/dev/null || true;     losetup -d "$L7" || true; L7=""

# ---------------------------------------------------------------------------
step "3/6 Copiando imagem original → $OUT"
cp --sparse=always "$SRC" "$OUT"

# ---------------------------------------------------------------------------
step "4/6 Aplicando customizações na p8 (/storage)"
L8="$(attach_part "$OUT" 8)"
e2fsck -fp "$L8" >/dev/null 2>&1 || warn "e2fsck reportou correções/avisos na p8 (código $?)"
mkdir -p "$MNT/p8"
mount -t ext4 "$L8" "$MNT/p8"

CONF="$MNT/p8/.config/emuelec/configs/emuelec.conf"
[[ -f "$CONF" ]] || { echo "emuelec.conf não encontrado em $CONF" >&2; exit 1; }
ORIG_COPY="$(mktemp)"; cp "$CONF" "$ORIG_COPY"
for kv in "${KV[@]}"; do set_kv "$CONF" "${kv%%=*}" "${kv#*=}"; done

# Overlay de arquivos (opcional): custom/overlay/p8/... é copiado por cima de /storage
if [[ -d "$CUSTOM/overlay/p8" ]]; then
  echo "  Copiando overlay custom/overlay/p8/ → /storage"
  cp -rT --no-preserve=ownership "$CUSTOM/overlay/p8" "$MNT/p8"
  # O bit de execução não sobrevive ao checkout no Windows: garante nos .sh do overlay
  (cd "$CUSTOM/overlay/p8" && find . -name '*.sh') | while read -r f; do chmod 755 "$MNT/p8/$f"; done
fi

echo
echo "  Diferença no emuelec.conf:"
diff -u --label emuelec.conf.fabrica --label emuelec.conf.custom "$ORIG_COPY" "$CONF" | sed 's/^/    /' || true
rm -f "$ORIG_COPY"

sync
umount "$MNT/p8"
e2fsck -fn "$L8" >/dev/null 2>&1 && echo "  p8 íntegra (e2fsck)." || warn "e2fsck -n encontrou problemas na p8"
losetup -d "$L8"; L8=""

# p2: logo de boot e telas de bateria (montados e validados em $P2DIR antes do passo 1)
if [[ -n "$(ls -A "$P2DIR")" ]]; then
  echo "  Copiando p2 (Volumn): $(cd "$P2DIR" && find . -type f | sed 's|^\./||' | tr '\n' ' ')"
  L2="$(attach_part "$OUT" 2)"
  mkdir -p "$MNT/p2"
  mount -t vfat "$L2" "$MNT/p2"
  cp -rT --no-preserve=all "$P2DIR" "$MNT/p2"
  sync; umount "$MNT/p2"
  losetup -d "$L2"; L2=""
fi

# ---------------------------------------------------------------------------
step "5/6 ROMs na p1 (/storage/roms)"
if [[ ${#COPY[@]} -eq 0 ]]; then
  echo "  Nada a copiar (use --roms <pasta> e/ou scripts/fetch-freeware.sh)."
else
  # Estica só a p1: aumenta o arquivo e troca o tamanho (LBA, 4 bytes LE) da 1ª entrada da MBR.
  # A tabela sunxi-mbr do bootloader já define a UDISK (p1) como "até o fim do disco".
  truncate -s "$need" "$OUT"
  h=$(printf %08x "$P1_NEW")
  printf "\x${h:6:2}\x${h:4:2}\x${h:2:2}\x${h:0:2}" | dd of="$OUT" bs=1 seek=458 conv=notrunc status=none
  read -r _ n < <(partx -g -o START,SECTORS -n 1 "$OUT")
  (( n == P1_NEW )) || { echo "Falha ao atualizar a MBR (p1 = $n setores)" >&2; exit 1; }

  # Recria o FAT32 no novo tamanho (mesmo serial) e devolve o conteúdo de fábrica.
  # O EmuELEC monta a p1 por dispositivo (/dev/mmcblk0p1), não por UUID/label.
  L1S="$(attach_part "$SRC" 1 --read-only)"
  L1="$(attach_part "$OUT" 1)"
  mkfs.vfat -F 32 -i "$(blkid -s UUID -o value "$L1S" | tr -d -)" "$L1" >/dev/null
  mkdir -p "$MNT/p1src" "$MNT/p1"
  mount -t vfat -o ro,utf8 "$L1S" "$MNT/p1src"
  mount -t vfat -o utf8 "$L1" "$MNT/p1"
  cp -rT "$MNT/p1src" "$MNT/p1"
  umount "$MNT/p1src"; losetup -d "$L1S"; L1S=""

  for c in "${COPY[@]}"; do
    echo "  Copiando ${c%%|*} → p1/${c#*|}"
    cp -rT "${c%%|*}" "$MNT/p1/${c#*|}"
  done
  sync
  df -h --output=size,used,avail "$MNT/p1" | sed 's/^/    /'
  umount "$MNT/p1"
  fsck.vfat -n "$L1" >/dev/null 2>&1 && echo "  p1 íntegra (fsck.vfat)." || warn "fsck.vfat -n encontrou problemas na p1"
  losetup -d "$L1"; L1=""
fi

# ---------------------------------------------------------------------------
step "6/6 Pronto"
echo "  Imagem gerada: $OUT"
echo "  SHA-256      : $(sha256sum "$OUT" | cut -d' ' -f1)"
echo
echo "  Grave no cartão SD com balenaEtcher, Rufus (modo DD) ou Win32DiskImager."
echo "  Guarde o cartão original de fábrica até validar a nova imagem no console."
