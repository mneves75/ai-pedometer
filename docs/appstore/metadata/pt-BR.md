# Metadata App Store - pt-BR

Arquivos canônicos de envio: `store/app-store/` (formato `asc metadata`, validados com
`asc metadata validate --dir store/app-store --check-urls`).

## App Information

- Categoria principal: `Saúde e fitness`
- Categoria secundária: `Estilo de vida`
- Preço: download pago, `R$ 1,99` no território-base Brasil (price point em `store/app-store/pricing.json`), demais territórios equalizados pela Apple

## Textos da ficha

Nome, subtítulo, texto promocional, descrição, keywords e as URLs de marketing, privacidade e suporte ficam em
`store/app-store/app-info/pt-BR.json` e `store/app-store/version/<versão>/pt-BR.json`.
A primeira versão na App Store não tem texto de Novidades.

## Contrato de licença

- Contrato de licença: EULA padrão da Apple (vale automaticamente; o app não tem assinatura)

## Privacidade do app

Arquivo canônico: `store/app-store/privacy.json` (formato `asc web privacy`).

- Coleta de dados: `Dados não coletados`. Nada é enviado ao desenvolvedor nem a terceiros; a Apple processa
  a compra na App Store e a gorjeta opcional como controladora independente.
- Usado para rastreamento: `Não`

## App Review Information

- Demo account required: `Não`
- Sign-in required: `Não`
- Notes para revisão (em inglês no ASC):
  - `Paid app (one-time purchase). There is no subscription: every feature is available without further purchase.`
  - `Only in-app purchase: optional Tip Jar (consumable), com.mneves.aipedometer.coffee. It unlocks nothing.`
  - `Tip Jar access path: More > Support AI Pedometer > Buy me a coffee`
  - `AI processing is on-device via Apple Foundation Models; no cloud AI service is used. AI features need a device with Apple Intelligence turned on.`
  - `Expedition Mode and GPX route import are in the Workouts tab.`

## Screenshot set (ordem sugerida)

1. Dashboard
2. AI Coach
3. Workouts
4. Training Plans
5. History
6. Badges
7. Active Workout
8. About - Tip Jar
