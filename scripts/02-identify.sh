#!/usr/bin/env bash
# 02-identify.sh — Identifica o conteúdo das áreas "raw" da imagem
# (bootloader, p5, p6) e do SYSTEM (squashfs do EmuELEC). SOMENTE LEITURA.
#
# Também copia essas áreas binárias para work/raw/ para análise posterior.
#
# Uso (WSL, na raiz do repositório):
#   sudo bash scripts/02-identify.sh "SISTEMA R36S GA36-MB V1.2-20260416.img"

set -euo pipefail

IMG="${1:-}"
[[ -n "$IMG" ]] || { echo "uso: sudo $0 <imagem.img>" >&2; exit 1; }
[[ $EUID -eq 0 ]] || { echo "Rode com sudo." >&2; exit 1; }
[[ -f "$IMG" ]]   || { echo "Imagem não encontrada: $IMG" >&2; exit 1; }

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$REPO_DIR/work"
RAW="$WORK/raw"
MNT="$WORK/mnt2"
REPORT="$REPO_DIR/reports/identify-$(date +%Y%m%d-%H%M%S).txt"
mkdir -p "$RAW" "$MNT" "$REPO_DIR/reports"

L7="" ; LSYS="" ; L8=""
cleanup() {
  # Ordem importa: o squashfs está dentro da p7
  mountpoint -q "$MNT/system" 2>/dev/null && umount "$MNT/system" || true
  [[ -n "$LSYS" ]] && losetup -d "$LSYS" 2>/dev/null || true
  mountpoint -q "$MNT/p7" 2>/dev/null && umount "$MNT/p7" || true
  mountpoint -q "$MNT/p8" 2>/dev/null && umount "$MNT/p8" || true
  [[ -n "$L7" ]] && losetup -d "$L7" 2>/dev/null || true
  [[ -n "$L8" ]] && losetup -d "$L8" 2>/dev/null || true
  rmdir "$MNT"/* "$MNT" 2>/dev/null || true
}
trap cleanup EXIT
exec > >(tee "$REPORT") 2>&1

section() { printf '\n==================== %s ====================\n' "$1"; }

# Retorna "START SECTORS" da partição N
part_geom() { partx -g -o START,SECTORS -n "$1" "$IMG"; }

# Mostra assinatura, tipo (file) e cabeçalho de um arquivo binário
describe_bin() {
  local f="$1"
  echo "Arquivo  : $f ($(stat -c %s "$f") bytes)"
  echo "file     : $(file -b "$f" 2>/dev/null || echo '?')"
  echo "Cabeçalho (64 bytes):"
  od -A x -t x1z -N 64 "$f"
  echo
  echo "Assinaturas conhecidas encontradas (offset: nome):"
  local found=0
  while IFS=: read -r off sig; do
    found=1
    case "$sig" in
      'ANDROID!') name='Android boot image (kernel+ramdisk)';;
      'RSCE')     name='Rockchip resource image (DTB + logos)';;
      'RKNS')     name='Rockchip idbloader';;
      'LOADER  ') name='Rockchip U-Boot/Trust loader';;
      'hsqs')     name='SquashFS';;
      *)          name="$sig";;
    esac
    printf '  0x%08x: %s\n' "$off" "$name"
  done < <(grep -aboE 'ANDROID!|RSCE|RKNS|LOADER  |hsqs' "$f" 2>/dev/null | head -n 20)
  [[ $found -eq 1 ]] || echo "  (nenhuma)"
  echo
  echo "Quantidade de DTBs (magic d00dfeed):"
  { LC_ALL=C grep -aobP '\xd0\x0d\xfe\xed' "$f" 2>/dev/null || true; } | wc -l
  echo
  echo "Pistas de SoC / placa / versão (strings):"
  LC_ALL=C grep -aoE 'rockchip,[a-z0-9,-]+|allwinner,[a-z0-9,-]+|amlogic,[a-z0-9,-]+|rk3[0-9]{3}[a-z0-9-]*|sun50i[a-z0-9-]*|U-Boot 20[0-9.]+[^ ]*|Linux version [0-9][^ ]*' "$f" 2>/dev/null \
    | sort | uniq -c | sort -rn | head -n 25 || true
}

section "IMAGEM"
echo "Arquivo: $IMG"
echo "Data   : $(date -Iseconds)"

section "ÁREA DE BOOTLOADER (setor 0 até início da p2)"
read -r P2_START _ < <(part_geom 2)
dd if="$IMG" of="$RAW/bootloader.bin" bs=512 count="$P2_START" status=none
describe_bin "$RAW/bootloader.bin"

for n in 5 6; do
  section "PARTIÇÃO p$n (raw)"
  read -r start sectors < <(part_geom "$n")
  echo "Início: setor $start | Tamanho: $sectors setores ($((sectors / 2048)) MiB)"
  dd if="$IMG" of="$RAW/p$n.bin" bs=512 skip="$start" count="$sectors" status=none
  describe_bin "$RAW/p$n.bin"
done

section "p7 (EMUELEC) → arquivo SYSTEM"
read -r start sectors < <(part_geom 7)
L7="$(losetup --find --show --read-only --offset $((start * 512)) --sizelimit $((sectors * 512)) "$IMG")"
mkdir -p "$MNT/p7"
mount -t vfat -o ro "$L7" "$MNT/p7"
ls -la "$MNT/p7"
echo
echo "file SYSTEM: $(file -b "$MNT/p7/SYSTEM")"
if command -v unsquashfs >/dev/null; then
  echo
  unsquashfs -s "$MNT/p7/SYSTEM" 2>/dev/null | head -n 20 || true
else
  echo "(instale squashfs-tools para ver detalhes do squashfs)"
fi

LSYS="$(losetup --find --show --read-only "$MNT/p7/SYSTEM")"
mkdir -p "$MNT/system"
if mount -t squashfs -o ro "$LSYS" "$MNT/system" 2>/dev/null; then
  S="$MNT/system"
  echo
  echo "--- etc/os-release ---";   cat "$S/etc/os-release" 2>/dev/null || true
  echo "--- etc/release ---";      cat "$S/etc/release"    2>/dev/null || true
  echo "--- usr/config/EE_VERSION ---"; cat "$S/usr/config/EE_VERSION" 2>/dev/null || true
  # Atenção: no SYSTEM, "lib" é symlink ABSOLUTO para /usr/lib — seguir "$S/lib"
  # cairia no /usr/lib do próprio WSL. Sempre usar caminhos reais (usr/...).
  echo "--- Módulos de kernel (usr/lib/modules) ---"; ls "$S/usr/lib/modules" 2>/dev/null || true
  echo "--- Raiz do SYSTEM ---";   ls -la "$S"
  echo "--- usr/config (padrões copiados p/ /storage) ---"; ls "$S/usr/config" 2>/dev/null || true
  echo "--- Binários de emuladores/frontend em usr/bin (filtrado) ---"
  ls "$S/usr/bin" 2>/dev/null | grep -Ei 'emulationstation|retroarch|ppsspp|drastic|mupen|flycast|amiberry|scummvm|dosbox|portmaster' || true
  echo "--- Scripts de inicialização (usr/lib/systemd/system, filtrado) ---"
  ls "$S/usr/lib/systemd/system" 2>/dev/null | grep -Ei 'emu|es|retro|storage|wifi|ssh|samba|splash' || true
  echo "--- DTBs dentro do SYSTEM ---"
  find "$S" -iname '*.dtb' 2>/dev/null | head -n 20 || true
else
  echo "FALHA ao montar o squashfs SYSTEM"
fi

section "p8 (/storage do EmuELEC)"
read -r start sectors < <(part_geom 8)
L8="$(losetup --find --show --read-only --offset $((start * 512)) --sizelimit $((sectors * 512)) "$IMG")"
mkdir -p "$MNT/p8"
mount -t ext4 -o ro,noload "$L8" "$MNT/p8"
echo "--- init.log ---"; cat "$MNT/p8/init.log" 2>/dev/null || true
echo "--- .config ---";  ls "$MNT/p8/.config" 2>/dev/null || true
echo "--- emuelec.conf (principais chaves) ---"
grep -Ev '^\s*(#|$)' "$MNT/p8/.config/emuelec/configs/emuelec.conf" 2>/dev/null | head -n 60 || true
echo "--- Temas do EmulationStation ---"
ls "$MNT/p8/.config/emulationstation/themes" "$MNT/p8/.config/emuelec/themes" 2>/dev/null || true

section "ARQUIVOS BRUTOS SALVOS"
ls -la "$RAW"

section "FIM"
echo "Relatório salvo em: $REPORT"
