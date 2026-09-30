# CLAUDE.md — Contexto do projeto

Projeto para **desmontar, customizar e remontar** a imagem de sistema de um console
"R36S clone" com placa **GA36-MB V1.2-20260416**. Repositório:
`git@github.com:thiagoaugust/r36s-GA35-MB-V-1-1-20251025.git`
(o nome do repo diz GA35/V1.1, mas a placa real é **GA36-MB V1.2** — renomear está pendente).

## Como trabalhar comigo

- Responder em **português (pt-BR)**.
- Fazer **uma pergunta por vez** e avançar passo a passo.
- Questionar se algo parecer estranho ou contradizer uma decisão anterior.
- Eu rodo os scripts no **WSL2 (Ubuntu)** no Windows. Pasta no Windows:
  `C:\Users\Pichau\dev-workspace\r36s-GA35-MB-V-1-1-20251025`
  (no WSL: `/mnt/c/Users/Pichau/dev-workspace/r36s-GA35-MB-V-1-1-20251025`).
  Se o Claude Code estiver rodando no Windows, execute os scripts via `wsl sudo bash scripts/...`.

## Fatos descobertos (ver `docs/layout-imagem.md` para detalhes)

- **SoC Allwinner A33** (sun8i, ARM 32 bits) — NÃO é Rockchip RK3326 como o R36S original.
  ArkOS / dArkOS / ROCKNIX / AmberELEC **não servem**.
- Sistema: **EmuELEC 4.7** fork do fabricante (`GA36-UDT-EE-TF-R-20250818`, `boardType=g80`).
- Kernel Linux **3.4.39** (BSP Allwinner), U-Boot 2017.09. Hardware configurado via **script.bin/FEX**, não DTB.
- Dump original: `SISTEMA R36S GA36-MB V1.2-20260416.img` (2.628.861.440 bytes),
  SHA-256 `550e071d117929ddc373572964bc544c18f03f510a06bda01832089e41eba9ad`.
- Partições (MBR, fora de ordem, extended começa no setor 1 — layout Allwinner/PhoenixCard):
  - área 0–73.727: MBR + boot0/U-Boot (**não mexer**)
  - p2 FAT16 `Volumn`: `bootlogo.bmp`, `bat/*.bmp`, fontes `.sft`, `magic.bin`
  - p5 raw: ambiente do U-Boot · p6 raw: Android bootimg (kernel + ramdisk)
  - p7 FAT32 `EMUELEC`: `SYSTEM` (squashfs **lzo**, bloco 512 KiB)
  - p8 ext4: `/storage` (`.config/emuelec/configs/emuelec.conf`, `emulationstation`, `retroarch`, `cores/`)
  - p1 FAT32: ROMs/BIOS (no fim do disco; expandida no 1º boot)
- Config de fábrica: `es_MX`, `America/Mexico_City`, hostname `UDT`, SSH ligado, `updates.enabled=1`, tema `NES-BOX`.

## Decisões tomadas

1. Customizar **sobre o EmuELEC do fabricante**, sem portar outro sistema.
2. **Nunca recriar a tabela de partições nem mexer no bootloader.** O build copia o dump
   original e aplica mudanças **dentro** das partições da cópia.
3. A imagem `.img` **nunca** vai para o Git (tamanho + ROMs/BIOS). `work/`, `out/`, `build/` são ignorados.
4. Scripts em bash com fim de linha **LF** (`.gitattributes`). Montagem sempre por loop com
   `--offset/--sizelimit` (o `--partscan` não é confiável no WSL).
5. No SYSTEM, `lib`/`bin`/`sbin` são symlinks absolutos: ao inspecionar pelo WSL, usar `usr/lib`, `usr/bin`.
6. Customizações versionadas em `custom/`:
   - `custom/emuelec.conf.d/*.conf` → pares `chave=valor` aplicados em ordem ao `emuelec.conf`
   - `custom/overlay/p8/` → arquivos copiados por cima do `/storage` (opcional)

## Estrutura

| Arquivo | Função |
|---|---|
| `scripts/01-inspect.sh` | Inspeciona partições (somente leitura) → `reports/inspect-*.txt` |
| `scripts/02-identify.sh` | Identifica bootloader/p5/p6/SYSTEM, copia áreas raw p/ `work/raw/` → `reports/identify-*.txt` |
| `scripts/03-build.sh` | Copia o original p/ `out/`, valida e aplica `custom/` na p8, mostra diff |
| `custom/emuelec.conf.d/10-localizacao-br.conf` | pt_BR, America/Sao_Paulo, hostname R36S, updates off |
| `docs/layout-imagem.md` | Mapa completo da imagem e onde mora cada customização |

## Estado atual

- [x] Inspeção e identificação da imagem
- [x] Build com a 1ª customização (localização BR) — testado só em imagem falsa
- [x] `03-build.sh` na imagem real (2026-09-30): sem `[AVISO]` → `out/r36s-custom-20260930-100203.img`
- [x] Gravado no SD e validado no console (2026-09-30) — boot OK com a customização BR
- [ ] **Primeiro commit** + push (nada foi commitado ainda)
- [ ] Renomear repo/README para GA36-MB V1.2

## Próximas customizações (backlog, escolhidas pelo usuário)

- Visual: logo de boot (p2 `bootlogo.bmp`, BMP de 921.654 bytes — conferir resolução), telas de bateria, tema do EmulationStation, splash
- Emuladores/configs: RetroArch, shaders, mapeamento de controles
- Sistema: senha do SSH, Wi-Fi, Samba, pacotes/serviços (exige unsquashfs → mksquashfs **-comp lzo -b 524288**)
