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

## Classificação etária e direitos de conteúdo

- Classificação etária: todos os itens `Nenhum`/`Não`, exceto Temas de saúde ou bem-estar = `Sim`
  (recomendações de exercício), o que classifica o app como 9+. O Coach IA não é Mensagens e chat, que a
  Apple define como usuários conversando entre si, e os links abrem fora do app, sem acesso irrestrito à web.
- Direitos de conteúdo: `Não usa conteúdo de terceiros`.

## App Review Information

- Demo account required: `Não`
- Sign-in required: `Não`
- Notas para revisão: `store/app-store/review.json` (aplicadas como estão, em inglês; `StoreListingTests`
  impede que o plano Premium removido volte a elas). O contato fica só no App Store Connect.
- Tip Jar: consumível `com.mneves.aipedometer.coffee` (`store/app-store/tip-jar.json`), Mais > Apoie o AI
  Pedometer > Me pague um café. Como é a primeira compra no app, vai para revisão junto com a versão.

## Screenshots enviados na 1.0.8

- iPhone 6,5" (capturados em 6,9"): Painel, Coach IA, Treinos, Planos de Treino, Histórico, Medalhas, Introdução.
- iPad 13": Painel, Histórico, Treinos, Medalhas.
- Apple Watch: capturas 416x496 do resumo de passos do relógio (obrigatórias porque o app inclui um app de relógio).
- Capturados num build Debug com dados de demonstração e IA no aparelho. Gorjeta e Treino Ativo ficaram de
  fora: no simulador a gorjeta não mostra preço e o treino não inicia.
