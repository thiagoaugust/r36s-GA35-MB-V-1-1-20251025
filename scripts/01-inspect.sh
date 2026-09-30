#!/usr/bin/env bash
# 01-inspect.sh — Inspeciona a imagem do R36S em modo SOMENTE LEITURA
# e gera um relatório em reports/. Não altera nada na imagem.
#
# Uso (dentro do WSL, na raiz do repositório):
#   sudo ./scripts/01-inspect.sh "SISTEMA R36S GA36-MB V1.2-20260416.img"
#
# Opções:
#   --no-hash   pula o cálculo de SHA-256 (mais rápido)

set -euo pipefail

DO_HASH=1
IMG=""
for arg in "$@"; do
  case "$arg" in
    --no-hash) DO_HASH=0 ;;
    *) IMG="$arg" ;;
  esac
done

if [[ -z "$IMG" ]]; then
  echo "uso: sudo $0 [--no-hash] <imagem.img>" >&2
  exit 1
fi
if [[ $EUID -ne 0 ]]; then
  echo "Este script precisa de root (losetup/mount). Rode com sudo." >&2
  exit 1
fi
if [[ ! -f "$IMG" ]]; then
  echo "Imagem não encontrada: $IMG" >&2
  exit 1
fi

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MNT_BASE="$REPO_DIR/work/mnt"
REPORT_DIR="$REPO_DIR/reports"
REPORT="$REPORT_DIR/inspect-$(date +%Y%m%d-%H%M%S).txt"
mkdir -p "$MNT_BASE" "$REPORT_DIR"

LOOPS=()
cleanup() {
  for m in "$MNT_BASE"/p*; do
    [[ -d "$m" ]] || continue
    if mountpoint -q "$m"; then umount "$m" || true; fi
    rmdir "$m" 2>/dev/null || true
  done
  for l in "${LOOPS[@]:-}"; do
    [[ -n "$l" ]] && losetup -d "$l" 2>/dev/null || true
  done
}
trap cleanup EXIT

# Tudo que for impresso vai para a tela e para o relatório
exec > >(tee "$REPORT") 2>&1

section() { printf '\n==================== %s ====================\n' "$1"; }

section "IMAGEM"
echo "Arquivo : $IMG"
echo "Tamanho : $(stat -c %s "$IMG") bytes"
echo "Data    : $(date -Iseconds)"
if [[ $DO_HASH -eq 1 ]]; then
  echo "Calculando SHA-256 (pode levar ~1 min em /mnt/c)..."
  echo "SHA-256 : $(sha256sum "$IMG" | cut -d' ' -f1)"
fi

section "TABELA DE PARTIÇÕES (fdisk)"
fdisk -l "$IMG" || true

section "TABELA DE PARTIÇÕES (parted)"
parted -s "$IMG" unit MiB print 2>/dev/null || echo "(parted indisponível)"

section "PARTIÇÕES (partx)"
partx -s -o NR,START,END,SECTORS,SIZE,TYPE,NAME "$IMG" || true

# Cria um loop por partição usando offset/tamanho — não depende de --partscan,
# que nem sempre cria /dev/loopXpN no WSL.
declare -A MOUNTED=()
while read -r n start sectors; do
  [[ -n "$n" ]] || continue
  loop="$(losetup --find --show --read-only \
          --offset $((start * 512)) --sizelimit $((sectors * 512)) "$IMG")"
  LOOPS+=("$loop")
  fstype="$(blkid -o value -s TYPE "$loop" 2>/dev/null || true)"
  label="$(blkid -o value -s LABEL "$loop" 2>/dev/null || true)"
  if [[ -z "$fstype" ]]; then
    echo "p$n: sem sistema de arquivos reconhecido (bootloader/raw?) — não montada"
    continue
  fi
  mp="$MNT_BASE/p$n"
  mkdir -p "$mp"
  opts="ro"
  [[ "$fstype" == ext* ]] && opts="ro,noload"
  if mount -t "$fstype" -o "$opts" "$loop" "$mp" 2>/dev/null; then
    MOUNTED[$n]="$fstype${label:+ label=$label}"
    echo "p$n: $fstype${label:+ ($label)} montada em $mp"
  else
    echo "p$n: $fstype${label:+ ($label)} — FALHA ao montar (tipo não suportado pelo kernel do WSL?)"
    rmdir "$mp" 2>/dev/null || true
  fi
done < <(partx -g -o NR,START,SECTORS "$IMG")

for n in $(printf '%s\n' "${!MOUNTED[@]}" | sort -n); do
  mp="$MNT_BASE/p$n"
  section "PARTIÇÃO p$n (${MOUNTED[$n]})"
  df -h "$mp" | tail -n1
  echo
  echo "--- Conteúdo da raiz ---"
  ls -la "$mp" || true

  echo
  echo "--- Arquivos de boot (dtb, kernel, ini, extlinux, uEnv) ---"
  find "$mp" -maxdepth 3 \( -iname '*.dtb' -o -iname 'Image' -o -iname 'zImage' \
    -o -iname 'uImage' -o -iname 'uInitrd' -o -iname 'initrd*' -o -iname 'boot.ini' \
    -o -iname 'extlinux.conf' -o -iname 'uEnv.txt' -o -iname 'boot.scr' \
    -o -iname '*.bmp' \) -printf '%10s  %p\n' 2>/dev/null || true

  if [[ -f "$mp/etc/os-release" ]]; then
    echo
    echo "*** Parece ser a ROOTFS ***"
    echo
    echo "--- /etc/os-release ---"
    cat "$mp/etc/os-release"
    echo
    echo "--- Hostname / issue ---"
    cat "$mp/etc/hostname" 2>/dev/null || true
    cat "$mp/etc/issue" 2>/dev/null || true
    echo
    echo "--- Kernels (lib/modules) ---"
    ls "$mp/lib/modules" 2>/dev/null || true
    echo
    echo "--- Pacotes instalados (dpkg) ---"
    if [[ -f "$mp/var/lib/dpkg/status" ]]; then
      echo "Total: $(grep -c '^Package:' "$mp/var/lib/dpkg/status")"
    else
      echo "(sem dpkg)"
    fi
    echo
    echo "--- Serviços systemd habilitados ---"
    ls "$mp/etc/systemd/system/multi-user.target.wants" 2>/dev/null || true
    echo
    echo "--- /opt ---"
    ls -la "$mp/opt" 2>/dev/null || true
    echo
    echo "--- Home dirs ---"
    ls -la "$mp/home" 2>/dev/null || true
    ls -la "$mp/root" 2>/dev/null || true
  fi

  echo
  echo "--- EmulationStation / RetroArch / temas / PortMaster ---"
  find "$mp" -maxdepth 6 \( -iname 'es_systems.cfg' -o -iname 'es_settings.cfg' \
    -o -iname 'es_input.cfg' -o -iname 'retroarch.cfg' -o -iname 'retroarch32.cfg' \
    -o -iname 'emulationstation' -o -ipath '*/themes' -o -iname 'PortMaster' \
    -o -iname '*_libretro.so' \) -printf '%p\n' 2>/dev/null | head -n 200 || true

  echo
  echo "--- Diretórios de primeiro nível (tamanho) ---"
  du -sh "$mp"/* 2>/dev/null | sort -h | tail -n 25 || true
done

section "FIM"
echo "Relatório salvo em: $REPORT"
