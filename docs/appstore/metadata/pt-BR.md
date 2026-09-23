# Metadata App Store - pt-BR

Arquivos canônicos de envio: `store/app-store/` (formato `asc metadata`, validados com
`asc metadata validate --dir store/app-store --check-urls --subscription-app`).

## App Information

- Categoria principal: `Saúde e fitness`
- Categoria secundária: `Estilo de vida`
- Preço: download pago, `R$ 1,99` no território-base Brasil (price point em `store/app-store/pricing.json`), demais territórios equalizados pela Apple

## Textos da ficha

Nome, subtítulo, texto promocional, descrição, keywords e as URLs de marketing, privacidade e suporte ficam em
`store/app-store/app-info/pt-BR.json` e `store/app-store/version/<versão>/pt-BR.json`.
A primeira versão na App Store não tem texto de Novidades.

## Contrato de licença

- Contrato de licença: EULA padrão da Apple (`https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`), com link na descrição e no paywall

## Privacidade do app

- Tipo de dado: `Compras > Histórico de compras`
- Finalidades: `Funcionalidade do app`, `Análises`
- Vinculado à identidade: `Não` (App User ID anônimo da RevenueCat; o app não tem conta)
- Usado para rastreamento: `Não`
- Coleta de Saúde e fitness: `Não`

## App Review Information

- Demo account required: `Não`
- Sign-in required: `Não`
- Notes para revisão:
  - `Tip Jar (IAP consumable): com.mneves.aipedometer.coffee`
  - `Produtos Premium: com.mneves.aipedometer.premium.monthly e com.mneves.aipedometer.premium.yearly`
  - `Entitlement da assinatura Premium AI: premium`
  - `A IA roda no dispositivo via Apple Foundation Models; nenhum serviço de IA em nuvem é usado.`
  - `Modo Expedição e importação de rotas GPX Premium ficam na aba Workouts.`
  - `Fluxos Premium: Workouts > Expedition Mode / Routes & GPX; Mais > Apoie o AI Pedometer > Premium`
  - `Fluxo do Tip Jar: Mais > Apoie o AI Pedometer > Comprar um café`
  - `Restaurar Compras e Gerenciar assinatura ficam na tela Premium.`

## Screenshot set (ordem sugerida)

1. Dashboard
2. AI Coach
3. Workouts
4. Training Plans
5. History
6. Badges
7. Active Workout
8. About - Tip Jar
