# R36S clone — GA36-MB V1.2-20260416

> Apesar do nome, esta placa usa **Allwinner A33** (não o Rockchip RK3326 do R36S original).
> O sistema de fábrica é um **EmuELEC 4.7** modificado pelo fabricante. Imagens de ArkOS/dArkOS/ROCKNIX **não** funcionam aqui.

Ferramentas e documentação para **desmontar, customizar e remontar** a imagem de sistema
do console R36S clone com placa **GA36-MB V1.2-20260416**.

> ⚠️ A imagem `.img` **não** é versionada neste repositório (tamanho e direitos autorais de ROMs/BIOS).
> Cada pessoa usa o dump do próprio console.

## Requisitos

- Windows com **WSL2 (Ubuntu)**
- Pacotes: `sudo apt install -y util-linux fdisk parted file squashfs-tools`

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

Customizações atuais:

- `10-localizacao-br.conf` — idioma `pt_BR`, fuso `America/Sao_Paulo`, hostname `R36S`, updates automáticos desligados.

```bash
sudo bash scripts/03-build.sh "SISTEMA R36S GA36-MB V1.2-20260416.img" --verify
```

A imagem original **não é alterada**. A saída vai para `out/r36s-custom-<data>.img` e o script mostra o diff do `emuelec.conf`.
