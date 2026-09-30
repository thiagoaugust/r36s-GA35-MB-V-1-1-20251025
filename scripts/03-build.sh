#!/usr/bin/env bash
# 03-build.sh — Gera uma imagem customizada a partir do dump ORIGINAL.
#
# O original nunca é alterado: o script copia a imagem para out/ e aplica,
# dentro da cópia, as customizações versionadas em custom/.
#
# Uso (WSL, na raiz do repositório):
#   sudo bash scripts/03-build.sh "SISTEMA R36S GA36-MB V1.2-20260416.img" [--out caminho.img] [--verify]
#
#   --out     caminho da imagem gerada (padrão: out/r36s-custom-<data>.img)
#   --verify  confere o SHA-256 do original com o registrado em docs/layout-imagem.md

set -euo pipefail

EXPECTED_SHA="550e071d117929ddc373572964bc544c18f03f510a06bda01832089e41eba9ad"
SRC="" ; OUT="" ; VERIFY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)    OUT="$2"; shift 2 ;;
    --verify) VERIFY=1; shift ;;
    *)        SRC="$1"; shift ;;
  esac
done

[[ -n "$SRC" ]] || { echo "uso: sudo $0 <imagem-original.img> [--out saida.img] [--verify]" >&2; exit 1; }
[[ $EUID -eq 0 ]] || { echo "Rode com sudo." >&2; exit 1; }
[[ -f "$SRC" ]]   || { echo "Imagem não encontrada: $SRC" >&2; exit 1; }

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CUSTOM="$REPO_DIR/custom"
OUT="${OUT:-$REPO_DIR/out/r36s-custom-$(date +%Y%m%d-%H%M%S).img}"
MNT="$REPO_DIR/work/build-mnt"
mkdir -p "$(dirname "$OUT")" "$MNT"

L7="" ; LSYS="" ; L8=""
cleanup() {
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

# ---------------------------------------------------------------------------
step "1/5 Verificando original"
echo "  Origem: $SRC"
if [[ $VERIFY -eq 1 ]]; then
  sha="$(sha256sum "$SRC" | cut -d' ' -f1)"
  if [[ "$sha" == "$EXPECTED_SHA" ]]; then echo "  SHA-256 confere."
  else warn "SHA-256 diferente do dump documentado ($sha). Continuando mesmo assim."; fi
fi
need=$(stat -c %s "$SRC")
free=$(df -B1 --output=avail "$(dirname "$OUT")" | tail -n1)
(( free > need )) || { echo "Espaço insuficiente em $(dirname "$OUT")" >&2; exit 1; }

# ---------------------------------------------------------------------------
step "2/5 Validando customizações contra o SYSTEM (somente leitura)"
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
        if find "$S/usr/share/locale/$val" "$S/usr/share/emulationstation" -maxdepth 3 \
             -ipath "*$val*" 2>/dev/null | grep -q .; then
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
step "3/5 Copiando imagem original → $OUT"
cp --sparse=always "$SRC" "$OUT"

# ---------------------------------------------------------------------------
step "4/5 Aplicando customizações na p8 (/storage)"
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
fi

echo
echo "  Diferença no emuelec.conf:"
diff -u --label emuelec.conf.fabrica --label emuelec.conf.custom "$ORIG_COPY" "$CONF" | sed 's/^/    /' || true
rm -f "$ORIG_COPY"

sync
umount "$MNT/p8"
e2fsck -fn "$L8" >/dev/null 2>&1 && echo "  p8 íntegra (e2fsck)." || warn "e2fsck -n encontrou problemas na p8"
losetup -d "$L8"; L8=""

# ---------------------------------------------------------------------------
step "5/5 Pronto"
echo "  Imagem gerada: $OUT"
echo "  SHA-256      : $(sha256sum "$OUT" | cut -d' ' -f1)"
echo
echo "  Grave no cartão SD com balenaEtcher, Rufus (modo DD) ou Win32DiskImager."
echo "  Guarde o cartão original de fábrica até validar a nova imagem no console."
