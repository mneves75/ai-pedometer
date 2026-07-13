# Guia Completo de RevenueCat no AIPedometer

## Objetivo

Este documento descreve, de ponta a ponta, como configurar, testar, operar e publicar a integração com a RevenueCat neste repositório.

Para um runbook direto de setup entre App Store Connect, Apple payments, StoreKit 2 e RevenueCat, veja [apple-payments-setup.md](apple-payments-setup.md).

O foco aqui não é uma integração genérica de iOS. O guia está alinhado ao estado real do projeto:

- app iOS SwiftUI
- SDK `RevenueCat` via Swift Package Manager
- paywall nativo em SwiftUI
- gating premium fail-closed
- sem sistema próprio de conta/login no app hoje
- `Tip Jar` separado da RevenueCat

## Resumo do desenho atual

Hoje o projeto usa RevenueCat apenas para o produto premium recorrente. O fluxo implementado é:

1. O app lê `REVENUECAT_API_KEY`, `REVENUECAT_ENTITLEMENT_ID` e `REVENUECAT_OFFERING_ID` de `Info.plist`, que por sua vez recebe os valores de `xcconfig`.
2. O `PremiumAccessStore` configura o SDK no bootstrap do app.
3. O app busca `Offerings` e `CustomerInfo`.
4. O entitlement configurado define se o usuário pode acessar recursos premium.
5. A UI apresenta o paywall oficial da RevenueCat via `RevenueCatUI`, enquanto o app mantém um store próprio para `purchase`, `restorePurchases`, `syncPurchases`, estado de entitlement e gates premium.
6. A tela About também pode abrir o Customer Center oficial da RevenueCat quando faz sentido.

Arquivos principais:

- [project.yml](../../project.yml)
- [Config/Local.xcconfig.example](../../Config/Local.xcconfig.example)
- [AIPedometer/Resources/Info.plist](../../AIPedometer/Resources/Info.plist)
- [Shared/Constants/AppConstants.swift](../../Shared/Constants/AppConstants.swift)
- [Shared/Utilities/LaunchConfiguration.swift](../../Shared/Utilities/LaunchConfiguration.swift)
- [AIPedometer/Core/Monetization/PremiumAccessStore.swift](../../AIPedometer/Core/Monetization/PremiumAccessStore.swift)
- [AIPedometer/Core/Monetization/PremiumAccessViews.swift](../../AIPedometer/Core/Monetization/PremiumAccessViews.swift)

## O que é premium neste app

No estado atual do produto, o entitlement premium controla:

- AI Insights no Dashboard
- AI Weekly Analysis no History
- AI Coach
- Smart Reminders
- criação de Training Plans
- recomendações AI de workout em Workouts
- Expedition Mode em Workouts
- importação de rotas GPX em Workouts
- telas/CTAs de upgrade e gerenciamento de assinatura

O `Tip Jar` não faz parte da RevenueCat. Ele continua separado via StoreKit e usa `com.mneves.aipedometer.coffee`.

## Conceitos da RevenueCat que este repo usa

A RevenueCat organiza monetização em três níveis:

- `Products`: os SKUs reais da loja, por exemplo mensal e anual.
- `Entitlements`: o acesso concedido no app, por exemplo `premium`.
- `Offerings`: o agrupamento que a UI exibe ao usuário.

Para este projeto, a modelagem recomendada é:

- Entitlement: `premium`
- Offering principal: `default` ou um offering customizado apontado por `REVENUECAT_OFFERING_ID`
- Packages típicos:
  - mensal
  - anual
  - opcionalmente lifetime, se o produto existir

Se `REVENUECAT_OFFERING_ID` ficar vazio, o app usa `currentOffering` retornado pelo SDK. Se você definir um identificador, o app vai procurar exatamente esse offering.

Nome recomendado do entitlement no dashboard:

- display name: `AI Pedometer Pro`
- identifier técnico no app: `premium`

## Pré-requisitos

Antes de mexer na RevenueCat, confirme:

- app já existe no App Store Connect
- bundle ID final está correto: `com.mneves.aipedometer`
- produtos de assinatura já existem ou serão criados no App Store Connect
- capability de In-App Purchase está habilitada no app
- você tem acesso para gerar chaves em App Store Connect

Também confirme que o arquivo local de configuração está fora do git:

- `Config/Local.xcconfig` já está ignorado em [`.gitignore`](../../.gitignore)

## Passo 1: configurar o App Store Connect

### 1. Criar os produtos de assinatura

No App Store Connect:

1. Abra o app `AIPedometer`.
2. Vá para a área de In-App Purchases / Subscriptions.
3. Crie um grupo de assinaturas para o premium.
4. Crie os produtos que o paywall vai vender.

Sugestão de estrutura:

- `com.mneves.aipedometer.premium.monthly`
- `com.mneves.aipedometer.premium.yearly`

Boas práticas:

- mantenha IDs estáveis e explícitos
- não renomeie IDs depois que o app entrar em produção
- deixe o nome comercial flexível no dashboard/metadata, não no SKU

### 2. Gerar a In-App Purchase Key

Este passo é crítico para iOS com SDK moderno da RevenueCat.

No App Store Connect:

1. Vá em `Users and Access`.
2. Abra `Integrations`.
3. Entre em `In-App Purchase`.
4. Gere uma nova In-App Purchase Key.
5. Baixe o arquivo `.p8` e guarde em local seguro.
6. Copie o `Issuer ID`.

Sem essa chave, transações podem acontecer no device mas não serem registradas corretamente pela RevenueCat.

### 3. Validar a base Apple antes de seguir

Antes de tocar na RevenueCat, confirme:

- produtos estão no app certo
- bundle ID no App Store Connect bate com o do projeto
- a In-App Purchase Key está ativa
- você guardou o `.p8`
- você guardou o `Issuer ID`

## Passo 2: configurar o dashboard da RevenueCat

### 1. Criar o projeto/app da Apple

Na RevenueCat:

1. Crie ou abra o projeto do app.
2. Adicione um app da Apple/App Store.
3. Verifique bundle ID e nome.

### 2. Subir a In-App Purchase Key

Ainda na configuração do app Apple dentro da RevenueCat:

1. Abra a seção de credenciais do App Store.
2. Faça upload do `.p8`.
3. Preencha o `Issuer ID`.
4. Salve.
5. Aguarde a validação de credenciais.

Você quer sair desta etapa com status equivalente a credenciais válidas.

### 3. Importar produtos

Depois de conectar a app store:

1. Vá em `Product catalog`.
2. Importe os produtos do App Store Connect.
3. Confira se todos os product identifiers vieram com o mesmo casing e spelling.

### 4. Criar o entitlement

Crie um entitlement com:

- identifier: `premium`

Esse identificador precisa bater com o valor de `REVENUECAT_ENTITLEMENT_ID` no projeto.

### 5. Vincular produtos ao entitlement

Anexe todos os SKUs que devem liberar premium:

- mensal
- anual
- qualquer outro plano que deva liberar os recursos premium

### 6. Criar o offering

Crie um offering para o paywall:

- identificador recomendado: `default`

Adicione packages para os produtos. Exemplo:

- `monthly`
- `annual`

Se quiser usar um offering específico em vez do `default`, defina esse ID em `REVENUECAT_OFFERING_ID`.

### 7. Copiar a public Apple API key

No dashboard da RevenueCat:

1. Vá em `Project Settings`.
2. Abra `API Keys`.
3. Copie a chave pública específica da app Apple.

Essa é a chave que entra no app. Nunca use segredo privado no client.

## Passo 3: configurar o projeto localmente

### 1. Arquivo local

Copie o template:

```bash
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

Preencha:

```xcconfig
DEVELOPMENT_TEAM = SEU_TEAM_ID
APP_STORE_ID = 1234567890
REVENUECAT_API_KEY = appl_xxxxxxxxxxxxxxxxx
REVENUECAT_ENTITLEMENT_ID = premium
REVENUECAT_OFFERING_ID = default
```

Observações:

- `REVENUECAT_OFFERING_ID` pode ficar vazio se você quiser usar o offering marcado como atual/default na RevenueCat.
- o template atual usa `premium` como fallback de entitlement; mantenha isso se não houver motivo real para mudar.

### 2. Como a configuração entra no app

Hoje o caminho é:

1. `Debug.xcconfig` e `Release.xcconfig` incluem opcionalmente `Local.xcconfig`
2. `Info.plist` recebe os placeholders:
   - `RevenueCatAPIKey`
   - `RevenueCatEntitlementID`
   - `RevenueCatOfferingID`
3. `AppConstants.RevenueCat.resolveConfiguration()` resolve env vars e `Info.plist`
4. `PremiumAccessStore` consome essa configuração

Arquivos relevantes:

- [Config/Debug.xcconfig](../../Config/Debug.xcconfig)
- [Config/Release.xcconfig](../../Config/Release.xcconfig)
- [AIPedometer/Resources/Info.plist](../../AIPedometer/Resources/Info.plist)
- [Shared/Constants/AppConstants.swift](../../Shared/Constants/AppConstants.swift)

### 3. Como trocar chave por ambiente

O projeto atual suporta bem o fluxo simples de uma chave por `Local.xcconfig`.

Para produção, a recomendação operacional é:

- Debug/local: chave de Test Store ou sandbox, se você optar por esse fluxo
- Release/CI: chave pública Apple real

Se quiser endurecer isso mais tarde, o caminho é separar variáveis por configuração em `Debug.xcconfig` e `Release.xcconfig` ou injetar via CI.

## Passo 4: entender como o app usa a RevenueCat

### Bootstrap

O app inicializa a monetização no startup via [AIPedometerApp.swift](../../AIPedometer/App/AIPedometerApp.swift).

O store principal é [PremiumAccessStore.swift](../../AIPedometer/Core/Monetization/PremiumAccessStore.swift).

Responsabilidades:

- configurar o SDK uma vez
- habilitar Trusted Entitlements em modo informativo
- buscar offerings
- buscar `CustomerInfo`
- observar `customerInfoStream`
- decidir se premium está ativo
- executar compra, restore, sync e manage subscription

### Entitlement que libera acesso

O app considera premium ativo quando o entitlement configurado está ativo em `CustomerInfo`.

Na implementação atual:

- o app usa `PremiumAccessStore` como fonte única de verdade para `CustomerInfo`, `Offerings`, compra, restore, sync e gates premium
- o About usa `CustomerCenter` oficial da RevenueCat
- o paywall usa `PaywallView` oficial da RevenueCat somente quando o offering carregado tem Paywall v2 publicado (`Offering.hasPaywall == true`)
- quando há packages mas não há Paywall v2 publicado, o app renderiza o fallback nativo próprio para evitar o paywall padrão/debug da RevenueCat

Pontos importantes:

- se não há configuração válida, o app falha fechado
- se o SDK não está configurado, a UI mostra estado de assinatura indisponível
- a UI não “abre” recurso premium por ausência de resposta; ela bloqueia
- se a verificação de entitlements da RevenueCat falhar, o app bloqueia acesso premium mesmo com entitlement/produto ativo no payload

### Offering usado pelo app

A lógica é:

- se `REVENUECAT_OFFERING_ID` está preenchido: usar esse offering
- se está vazio: usar `currentOffering`

Isso é útil para:

- ter um offering default para produção
- trocar offering no dashboard sem subir binário
- usar um offering temporário em experimentos ou staging

### App User ID

O app não passa `appUserID` customizado hoje.

Na prática isso significa:

- RevenueCat gera um usuário anônimo automaticamente
- isso é aceitável para o estado atual do produto, porque o app não tem sistema próprio de login

Se o produto ganhar conta/login no futuro:

1. passe o App User ID no configure, ou
2. chame `logIn()` quando o usuário autenticar

Não introduza App User IDs customizados parcialmente. Ou a estratégia é toda anônima, ou é toda consistente por conta autenticada.

## Passo 5: testar localmente

Há três estratégias de teste relevantes.

### Estratégia A: flags de override do app

Útil para UI test, snapshots e validação de layout sem tocar na store:

- `-force-premium-on`
- `-force-premium-off`
- `PREMIUM_ENABLED=1`
- `PREMIUM_ENABLED=0`

Esses overrides funcionam apenas em builds **Debug**. Builds Release ignoram launch arguments e variáveis de ambiente por segurança (argumentos de launch são input controlável por atacante via `devicectl`).

Arquivos:

- [Shared/Utilities/LaunchConfiguration.swift](../../Shared/Utilities/LaunchConfiguration.swift)
- [AIPedometerUITests/Support/AppDriver.swift](../../AIPedometerUITests/Support/AppDriver.swift)

Uso prático:

- validar UI premium aberta sem compra real
- validar gates premium fechados
- reproduzir estados de paywall e de recurso bloqueado

### Estratégia B: RevenueCat Test Store

Boa para desenvolvimento rápido sem depender do App Store Connect completo.

Quando usar:

- você quer desenvolver a integração cedo
- ainda não terminou a configuração Apple
- quer testar compra rapidamente

Cuidados:

- nunca publique build com API key de Test Store
- não confunda esse caminho com o fluxo final de produção da app iOS

Para este repo, Test Store é útil em debug. Para ir a produção, valide também no ecossistema Apple.

### Estratégia C: Apple Sandbox / TestFlight

É a validação mais importante antes de produção.

Quando usar:

- antes de shippar
- para confirmar restore
- para conferir gestão de assinatura
- para validar vínculo real entre Apple e RevenueCat

Este deve ser o fluxo principal de release readiness.

## StoreKit Configuration neste repositório

O scheme atual aponta para:

- `StoreKit/TipJar.storekit`

Importante:

- esse arquivo cobre o `Tip Jar`
- ele não é a fonte de verdade do premium RevenueCat
- ele não valida, sozinho, a jornada final de assinatura premium

Se você quiser testar premium com StoreKit Configuration no simulador:

1. crie um arquivo StoreKit dedicado para as assinaturas premium
2. sincronize com App Store Connect, se aplicável
3. duplique o scheme
4. associe o novo arquivo ao scheme
5. faça upload do certificado público/artefatos exigidos pela RevenueCat para StoreKit testing

Mesmo assim, antes de produção, faça um passe real em Sandbox/TestFlight.

## Como usar a UI premium no app

Componentes principais:

- [PremiumAccessViews.swift](../../AIPedometer/Core/Monetization/PremiumAccessViews.swift)
- `PremiumFeatureGateCard`
- `PremiumSubscriptionCard`
- `PremiumAccessSheet`

Fluxos implementados:

- abrir paywall
- listar packages disponíveis
- comprar package
- restaurar compras
- abrir gestão de assinatura
- mostrar estado indisponível quando não há configuração válida

O app usa `PaywallView` oficial da `RevenueCatUI` quando a configuração é válida e o offering carregado tem Paywall v2 publicado (`Offering.hasPaywall == true`). Se o offering existe e contém packages, mas não tem Paywall v2 publicado, o app mostra o fallback nativo próprio com compra/restore/manage subscription em vez de chamar o paywall padrão da RevenueCat.

A lógica de acesso continua local e explícita:

- `PremiumAccessStore` é a fonte única de verdade para entitlement, offerings e estado de compra
- `PremiumAccessSheet` escolhe entre paywall oficial, fallback nativo com packages, ações de restore/manage e estado indisponível
- se RevenueCat não estiver configurado ou não retornar offerings válidos, a UI falha fechada

## Como os recursos premium são gated

Hoje o gating está espalhado em superfícies específicas:

- [AIPedometer/Features/Dashboard/DashboardView.swift](../../AIPedometer/Features/Dashboard/DashboardView.swift)
- [AIPedometer/Features/History/HistoryView.swift](../../AIPedometer/Features/History/HistoryView.swift)
- [AIPedometer/Features/AICoach/AICoachView.swift](../../AIPedometer/Features/AICoach/AICoachView.swift)
- [AIPedometer/Features/Settings/SettingsView.swift](../../AIPedometer/Features/Settings/SettingsView.swift)
- [AIPedometer/Features/TrainingPlans/TrainingPlansView.swift](../../AIPedometer/Features/TrainingPlans/TrainingPlansView.swift)
- [AIPedometer/Features/Workouts/WorkoutsView.swift](../../AIPedometer/Features/Workouts/WorkoutsView.swift)
- [AIPedometer/Features/About/AboutView.swift](../../AIPedometer/Features/About/AboutView.swift)

Regra operacional:

- recurso premium só abre se `premiumAccessStore.canAccessAIFeatures` for `true`
- caso contrário, mostrar gate ou estado indisponível

## Testes recomendados antes de produção

### Checklist mínimo

- [ ] app abre com `REVENUECAT_API_KEY` válida e sem warnings inesperados
- [ ] offerings carregam
- [ ] paywall mostra os produtos esperados
- [ ] compra mensal funciona em sandbox
- [ ] compra anual funciona em sandbox
- [ ] restore reativa o entitlement
- [ ] `Manage Subscription` abre corretamente
- [ ] usuário sem entitlement vê gates fechados
- [ ] usuário com entitlement vê recursos premium liberados
- [ ] build Release usa chave Apple real, não Test Store

### Comportamentos específicos do repo

Você também deve validar:

- Dashboard: insight premium libera corretamente
- History: análise semanal fica disponível
- AI Coach: conversa abre sem gate indevido
- Settings: Smart Reminders habilitam apenas com premium
- Training Plans: criação de plano abre paywall quando necessário
- Workouts: recomendação AI e card de plano respeitam entitlement
- Workouts: Expedition Mode e importação GPX ficam fechados sem entitlement e liberados com premium
- About: estado de assinatura e ações estão corretos

### Testes automatizados do repo

Cobertura já existente inclui:

- resolução de configuração RevenueCat
- overrides de premium por argumentos/env
- UI test de gates premium nos treinos

## Logs e observabilidade

No estado atual do código:

- em `DEBUG`, o app liga `Purchases.logLevel = .debug`
- falhas de refresh, restore, sync, purchase e manage subscription são logadas

Isso é útil para depurar:

- offering não carregando
- produto não importado
- credencial Apple inválida
- entitlement não sendo ativado

Durante implementação e testes, olhe primeiro:

- logs do Xcode
- logs da app
- dashboard da RevenueCat

## Troubleshooting

### O paywall abre, mas não há packages

Causas comuns:

- nenhum product importado
- produtos não vinculados ao entitlement
- offering vazio
- `REVENUECAT_OFFERING_ID` aponta para offering inexistente

### Aparece banner vermelho "Offering 'default' has no configured paywall"

Esse banner é da `RevenueCatUI` quando o app pede o paywall oficial para um offering sem Paywall v2 publicado. O app não deve chamar esse caminho nesse estado: `PremiumAccessSheet` usa `RevenueCatPaywallPolicy` e só renderiza `PaywallView(offering:)` quando `Offering.hasPaywall == true`.

Se quiser usar o editor visual da RevenueCat, publique o Paywall v2 no dashboard para o offering configurado. Se quiser vender pelos cards nativos do app, mantenha os packages no offering; o fallback próprio continua comprando/restaurando pelo `PremiumAccessStore`.

Verifique:

- RevenueCat `Product catalog`
- entitlement `premium`
- offering configurado
- valor de `REVENUECAT_OFFERING_ID`

### O app sempre mostra “Subscriptions are unavailable right now”

Esse é o comportamento fail-closed esperado quando:

- `REVENUECAT_API_KEY` está ausente
- a key ainda é placeholder
- `Info.plist` não recebeu expansão correta do `xcconfig`

Verifique:

- `Config/Local.xcconfig` se você já criou o arquivo a partir do template [Config/Local.xcconfig.example](../../Config/Local.xcconfig.example)
- [AIPedometer/Resources/Info.plist](../../AIPedometer/Resources/Info.plist)
- breakpoint/log em `AppConstants.RevenueCat.resolveConfiguration()`

### Compra ocorre, mas premium não libera

Causas mais comuns:

- produto não está ligado ao entitlement `premium`
- In-App Purchase Key não foi configurada corretamente
- offering/package no app não corresponde ao SKU comprado
- você está validando com build/chave errada

Verifique:

- entitlement `premium`
- products attached ao entitlement
- credenciais Apple válidas na RevenueCat
- chave pública Apple correta no app

### UI test fica premium mesmo sem compra

Lembre que o app entra em modo de teste automaticamente em XCTest.

Se você quiser validar os gates fechados, use:

- `-force-premium-off`

### `Manage Subscription` falha

O app primeiro tenta `showManageSubscriptions()`. Se isso falhar, usa `managementURL` quando disponível.

Se ainda assim falhar:

- confirme que existe assinatura ativa
- confirme ambiente sandbox/TestFlight adequado
- cheque logs do device/Xcode

## Checklist de produção

Antes de publicar:

- [ ] produtos reais criados no App Store Connect
- [ ] In-App Purchase Key configurada na RevenueCat
- [ ] Issuer ID preenchido corretamente
- [ ] status de credenciais validado na RevenueCat
- [ ] entitlement `premium` configurado
- [ ] offering pronto e compatível com o app
- [ ] build Release usa chave pública Apple real
- [ ] compra e restore validados em Apple Sandbox ou TestFlight
- [ ] sem dependência de Test Store em produção
- [ ] paywall e gates revisados em pt-BR e en

## Decisões específicas deste repo

Estas são decisões já tomadas no código:

- o app usa `RevenueCatUI` para o paywall oficial quando há offering/config válidos
- o app usa entitlement único `premium`
- o app usa usuário anônimo da RevenueCat, porque não há login
- o app falha fechado quando não há configuração válida
- o app mantém `Tip Jar` fora da RevenueCat

Se alguma dessas decisões mudar, atualize este guia junto com o código.

## Referências oficiais

Fontes oficiais usadas para este guia:

- RevenueCat Quickstart: https://www.revenuecat.com/docs/getting-started/quickstart
- RevenueCat SDK configuration: https://www.revenuecat.com/docs/getting-started/configuring-sdk
- RevenueCat product configuration: https://www.revenuecat.com/docs/projects/configuring-products
- RevenueCat Apple sandbox / StoreKit testing: https://www.revenuecat.com/docs/test-and-launch/sandbox/apple-app-store
- RevenueCat In-App Purchase Key configuration: https://www.revenuecat.com/docs/service-credentials/itunesconnect-app-specific-shared-secret/in-app-purchase-key-configuration

## TL;DR operacional

Se você só quer colocar para funcionar com segurança:

1. crie os SKUs no App Store Connect
2. gere a In-App Purchase Key e o Issuer ID
3. configure a app Apple na RevenueCat
4. importe os produtos
5. crie o entitlement `premium`
6. crie o offering `default`
7. copie a public Apple API key
8. preencha `Config/Local.xcconfig`
9. rode em sandbox/TestFlight
10. valide compra, restore e manage subscription antes de publicar
