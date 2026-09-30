# Layout da imagem — GA36-MB V1.2-20260416

Fontes: `reports/inspect-20260930-085031.txt`, `reports/identify-20260930-085750.txt`
SHA-256 do dump original: `550e071d117929ddc373572964bc544c18f03f510a06bda01832089e41eba9ad`
Tamanho: 2.628.861.440 bytes (5.134.495 setores de 512 B) — tabela MBR (`0x815d9b77`)

## Hardware / software identificados

| Item | Valor | Evidência |
|---|---|---|
| SoC | **Allwinner A33** (sun8i, ARM Cortex-A7 32 bits) — **não** é Rockchip RK3326 como o R36S original | `COREELEC_DEVICE="A33"`, `sun8i` no boot image |
| Bootloader | U-Boot 2017.09-g05bceb2-dirty | strings da área de bootloader |
| Kernel | Linux **3.4.39** (BSP Allwinner), Android boot image, kernel @ `0x40008000` | p6 |
| Config de hardware | BSP 3.4 usa **FEX/script.bin** (sys_config), não DTB — nenhum DTB encontrado | 0 magic `d00dfeed` |
| Módulos | `disp.ko`, `lcd.ko`, `mali.ko`, `gpio-sunxi.ko`, `udt_joystick.ko`, `cdc_ether.ko`, `meig_cdc_driver.ko` | `SYSTEM:/usr/lib/modules` |
| Sistema | **EmuELEC 4.7** (fork "Nexus_devel_20250822", build do fabricante "UDT") | `SYSTEM:/etc/os-release` |
| Versão do fabricante | `GA36-UDT-EE-TF-R-20250818`, `boardType=g80` | `emuelec.conf` |
| SYSTEM | squashfs 4.0, **lzo** (lzo1x_999 nível 9), bloco 512 KiB, 12.276 inodes | `unsquashfs -s` |

> Consequência: imagens de ArkOS / dArkOS / ROCKNIX / AmberELEC para R36S (RK3326) **não funcionam** nesta placa.
> A customização é feita **sobre o EmuELEC do fabricante**.

## Partições

| Part. | Setores (início–fim) | Tamanho | Tipo | Label | Conteúdo |
|---|---|---|---|---|---|
| — | 0 – 73.727 | 36 MiB | raw | — | MBR + boot0/U-Boot Allwinner (+ cópia de boot image @ `0x01320dd8`) |
| p2 | 73.728 – 335.871 | 128 MiB | FAT16 (ativa) | `Volumn` | Recursos de boot Allwinner: `bootlogo.bmp`, `bat/*.bmp`, `font24/32.sft`, `magic.bin` |
| p3 | 1 – 4.956.160 | 2,4 GiB | Extended | — | Contêiner das lógicas |
| p5 | 139.264 – 172.031 | 16 MiB | raw | — | **Ambiente do U-Boot** (`bootdelay=0`, `bootcmd=run setargs_mmc boot_normal`…) |
| p6 | 172.032 – 237.567 | 32 MiB | raw | — | **Boot**: Android bootimg (kernel 3.4.39 + ramdisk/initramfs) |
| p7 | 237.568 – 1.810.431 | 768 MiB | FAT32 | `EMUELEC` | `SYSTEM` (squashfs do SO, 406 MiB) + `low_pwr.bmp` |
| p8 | 1.810.432 – 4.956.159 | 1,5 GiB | ext4 | — | `/storage`: `.config/` (emuelec, emulationstation, retroarch…), `cores/`, `assets`, `shaders`, `overlays` |
| p1 | 4.956.160 – 5.134.494 | 87 MiB | FAT32 | — | ROMs/BIOS (`/storage/roms`) — **não** é expandida no boot; 1ª entrada da MBR; montada por dispositivo (`mount_romfs.sh`, vfat utf8) |

## Configuração de fábrica relevante (`/storage/.config/emuelec/configs/emuelec.conf`)

- `system.language=es_MX`, `system.timezone=America/Mexico_City`, `system.hostname=UDT`
- `ee_ssh.enabled=1` (SSH ligado de fábrica), `wifi.enabled=0`, `updates.enabled=1`
- `ee_videomode=1080p60hz`, `global.ratio=4/3`, `brightness.level=80`, `audio.volume=29`
- Tema do EmulationStation: `NES-BOX`

## Observações

- Tabela fora de ordem e extended começando no setor 1: layout típico de imagens Allwinner (PhoenixCard). **Não mexer na tabela**, exceto o tamanho da p1 (última partição), que o `03-build.sh --roms` estica.
- Há também uma tabela **sunxi-mbr** (`softw411`) a 20 MiB do início (partições relativas ao setor 40.960); a `UDISK` (= p1) tem `len=0`, ou seja, "até o fim do disco".
- `fs-resize` só roda se existir `/flash/.please_resize_me` (não existe) e, nesse caso, **reformata a p8** — não mexe na p1.
- `init.log` registra `fsck.auto: No such file or directory` — o fsck do /storage não roda no boot.
- No SYSTEM, `lib`/`bin`/`sbin` são symlinks **absolutos**; ao inspecionar pelo WSL use sempre `usr/lib`, `usr/bin`.

## Onde mora cada customização

| Objetivo | Onde | Dificuldade |
|---|---|---|
| Idioma, fuso, hostname, SSH, volume, brilho | p8 `.config/emuelec/configs/emuelec.conf` | Baixa |
| Tema / config do EmulationStation, controles | p8 `.config/emulationstation/` | Baixa |
| RetroArch, shaders, overlays, cores | p8 `.config/retroarch/`, `cores/`, `shaders/` | Baixa |
| Logo de boot, telas de bateria | p2 `bootlogo.bmp`, `bat/` (BMP 921.654 B — conferir resolução) | Baixa |
| Splash do EmuELEC | p8 `.config/splash/` | Baixa |
| Pacotes, serviços, scripts do SO | p7 `SYSTEM` (unsquashfs → editar → mksquashfs **lzo**) | Média |
| Kernel / ramdisk | p6 (desempacotar Android bootimg) | Alta |
| Hardware (tela, controles, som) | script.bin/FEX no bootloader | Alta — evitar |
