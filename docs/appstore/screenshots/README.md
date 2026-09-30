# Screenshots para upload no App Store Connect

As screenshots finais desta pipeline são geradas em:

- `output/appstore-publishing/screenshots/iphone_65`
- `output/appstore-publishing/screenshots/ipad_13`

Para gerar e validar:

```bash
bash Scripts/appstore-materials-prepare.sh
bash Scripts/appstore-screenshots-validate.sh
```

As fontes e os diretórios de saída devem ser separados, inclusive quando usam links
simbólicos. A preparação verifica os arquivos obrigatórios e converte as imagens em
staging antes de substituir o pacote anterior; falhas nessas etapas preservam o pacote.

Ou fluxo único:

```bash
bash Scripts/appstore-publishing-preflight.sh
```

Para upload:

```bash
bash Scripts/appstore-screenshots-upload.sh --version-localization-id "<LOC_ID>"
```
