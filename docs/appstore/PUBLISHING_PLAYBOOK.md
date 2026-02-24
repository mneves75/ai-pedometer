# Playbook de Publicação na App Store (AIPedometer)

## Objetivo

Este playbook define um fluxo repetível, de padrão industrial, para publicar versões do AIPedometer no App Store Connect com qualidade de revisão, consistência visual e rastreabilidade operacional.

## Padrão de mercado adotado

1. **Compliance-first (Apple)**: validar requisitos técnicos e metadata antes de subir build.
2. **Narrativa visual orientada a valor**: primeiras screenshots focadas em benefício principal do app (valor em até 3 telas).
3. **Automação de assets**: gerar, ordenar, validar dimensões e fazer upload por script.
4. **Release controlado**: TestFlight antes de produção e, quando aplicável, phased release.
5. **Iteração orientada por experimento**: usar Product Page Optimization quando houver volume de tráfego suficiente.

## Matrizes suportadas (ASC)

Conjunto mínimo recomendado pelo `asc screenshots sizes`:

- iPhone: `IPHONE_65` com `1284x2778` (ou equivalentes aceitos)
- iPad: `IPAD_PRO_3GEN_129` com `2064x2752` (ou equivalentes aceitos)

## Estrutura de materiais gerados

Após rodar o preparo:

- `output/appstore-publishing/screenshots/iphone_69` (captura base 1320x2868)
- `output/appstore-publishing/screenshots/iphone_65` (pronto para upload)
- `output/appstore-publishing/screenshots/ipad_13` (pronto para upload)

## Execução (fim a fim)

### Comando único (preflight recomendado)

```bash
bash Scripts/appstore-publishing-preflight.sh
```

Com upload dry-run já resolvendo localization:

```bash
bash Scripts/appstore-publishing-preflight.sh \
  --run-upload-dry-run \
  --app-id "<APP_ID_ASC>" \
  --version "0.71" \
  --locale "pt-BR"
```

### 1) Preparar screenshots

```bash
bash Scripts/appstore-materials-prepare.sh
```

### 2) Validar dimensões e integridade

```bash
bash Scripts/appstore-screenshots-validate.sh
```

### 3) Upload para App Store Connect

Opção A (ID de localization já conhecido):

```bash
bash Scripts/appstore-screenshots-upload.sh \
  --version-localization-id "<LOC_ID>"
```

Opção B (resolver automaticamente por app/version/locale):

```bash
bash Scripts/appstore-screenshots-upload.sh \
  --app-id "<APP_ID_ASC>" \
  --version "0.71" \
  --locale "pt-BR"
```

### 4) Metadata

Preencher e revisar:

- `docs/appstore/metadata/pt-BR.md`
- `docs/appstore/metadata/en-US.md`

### 5) Build, release e submissão

1. Gerar/validar build (`xcodebuild`, testes relevantes).
2. Publicar TestFlight para validação final interna.
3. Anexar build à versão da App Store.
4. Revisar metadata + screenshots + IAPs relacionados.
5. Submeter para review.
6. Após aprovado: liberar manualmente ou phased release.

## Checklist de envio

- [ ] Build correto anexado à versão.
- [ ] Screenshots válidas para iPhone e iPad.
- [ ] Metadata completa em pt-BR e en-US.
- [ ] Notes para review atualizadas.
- [ ] IAP de tip jar (`com.mneves.aipedometer.coffee`) pronto para venda.
- [ ] TestFlight validado para compra/sandbox.
- [ ] Plano de rollout (imediato ou phased release) definido.

## Evidências da execução desta rodada

- Capturas iPhone base: `output/appstore-capture-iphone/screens/ui/named`.
- Capturas iPad base: `output/appstore-capture-ipad/screens/onboarding/named`.
- Pacote final gerado em: `output/appstore-publishing/screenshots`.

## Referências oficiais

- App screenshots: https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications
- App previews: https://developer.apple.com/help/app-store-connect/reference/app-preview-specifications
- Product Page Optimization: https://developer.apple.com/app-store/product-page-optimization/
- In-App Purchases review: https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase
