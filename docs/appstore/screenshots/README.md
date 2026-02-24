# Screenshots para upload no App Store Connect

As screenshots finais desta pipeline são geradas em:

- `output/appstore-publishing/screenshots/iphone_65`
- `output/appstore-publishing/screenshots/ipad_13`

Para gerar e validar:

```bash
bash Scripts/appstore-materials-prepare.sh
bash Scripts/appstore-screenshots-validate.sh
```

Ou fluxo único:

```bash
bash Scripts/appstore-publishing-preflight.sh
```

Para upload:

```bash
bash Scripts/appstore-screenshots-upload.sh --version-localization-id "<LOC_ID>"
```
