# R36S clone — GA36-MB V1.2-20260416

> Apesar do nome, esta placa usa **Allwinner A33** (não o Rockchip RK3326 do R36S original).
> O sistema de fábrica é um **EmuELEC 4.7** modificado pelo fabricante. Imagens de ArkOS/dArkOS/ROCKNIX **não** funcionam aqui.

Ferramentas e documentação para **desmontar, customizar e remontar** a imagem de sistema
do console R36S clone com placa **GA36-MB V1.2-20260416**.

> ⚠️ A imagem `.img` **não** é versionada neste repositório (tamanho e direitos autorais de ROMs/BIOS).
> Cada pessoa usa o dump do próprio console.

## Requisitos

- Windows com **WSL2 (Ubuntu)**
- Pacotes: `sudo apt install -y util-linux fdisk parted file squashfs-tools dosfstools`

## Fluxo

| Etapa | Script | Status |
|---|---|---|
| 1. Inspecionar a imagem (somente leitura) | `scripts/01-inspect.sh` | ✅ |
| 2. Identificar bootloader, kernel/DTB e SYSTEM | `scripts/02-identify.sh` | ✅ |
| 3. Gerar imagem customizada (cópia do original + `custom/`) | `scripts/03-build.sh` | ✅ |
| 4. Gravar no SD e validar no console | — | 🔜 |

## Etapa 1 — Inspecionar

No WSL, na raiz do repositório:

```bash
cd "/mnt/c/Users/<usuario>/dev-workspace/r36s-GA35-MB-V-1-1-20251025"
chmod +x scripts/*.sh
sudo ./scripts/01-inspect.sh "SISTEMA R36S GA36-MB V1.2-20260416.img"
```

O relatório é salvo em `reports/inspect-<data>.txt`.
O mapa da imagem está documentado em [`docs/layout-imagem.md`](docs/layout-imagem.md).

## Etapa 2 — Identificar

```bash
sudo bash scripts/02-identify.sh "SISTEMA R36S GA36-MB V1.2-20260416.img"
```

Copia as áreas binárias (bootloader, p5, p6) para `work/raw/` e gera `reports/identify-<data>.txt`.

## Etapa 3 — Gerar imagem customizada

As customizações ficam versionadas em `custom/`:

| Caminho | O que faz |
|---|---|
| `custom/emuelec.conf.d/*.conf` | Pares `chave=valor` aplicados (em ordem) ao `emuelec.conf` do `/storage` |
| `custom/overlay/p8/` | (opcional) Arquivos copiados por cima do `/storage` |
| `custom/roms.list` | Sistemas (pastas) copiados de `--roms <pasta>` para a p1 (`/storage/roms`) |

Customizações atuais:

- `10-localizacao-br.conf` — idioma `pt_BR`, fuso `America/Sao_Paulo`, hostname `R36S`, updates automáticos desligados.
- `overlay/p8/.config/emulationstation/scripts/start/01-boot-beep.sh` — dois bipes quando o EmulationStation termina de iniciar.

```bash
sudo bash scripts/03-build.sh "SISTEMA R36S GA36-MB V1.2-20260416.img" --verify
```

A imagem original **não é alterada**. A saída vai para `out/r36s-custom-<data>.img` e o script mostra o diff do `emuelec.conf`.

### Jogos gratuitos (opcional)

```bash
bash scripts/fetch-freeware.sh
```

Baixa do Content Downloader oficial da libretro (com conferência de SHA-256) Doom e Quake shareware,
Cave Story, Dinothawr, Rick Dangerous e Wolfenstein 3D shareware para `work/freeware/`. Se essa pasta existir,
o `03-build.sh` copia o conteúdo para a p1. Os menus de Quake, Cave Story, Dinothawr e Rick Dangerous vêm de
`custom/es_systems_extra.cfg` (acrescentado ao `es_systems.cfg` no build); o Doom passa a usar o núcleo `prboom`
(`custom/emuelec.conf.d/20-doom-prboom.conf`), já que o Chocolate-Doom padrão não existe nesta imagem.

### Com ROMs

```bash
sudo bash scripts/03-build.sh "SISTEMA R36S GA36-MB V1.2-20260416.img" --verify --roms "/mnt/c/Users/<usuario>/Desktop/unidade e"
```

A pasta passada em `--roms` deve ter uma subpasta por sistema com o nome usado pelo EmulationStation
(`gb`, `gba`, `nes`, `snes`, `megadrive`…). O build copia as listadas em `custom/roms.list`, aumenta a
imagem e estica a p1 (última partição) para caber tudo — a imagem final fica maior que o original, então confira o tamanho do cartão.
