# Setup RevenueCat + pagamentos Apple

Este runbook explica como configurar o premium recorrente do AIPedometer usando App Store Connect, StoreKit 2 e RevenueCat.

Ele cobre o caminho de produção para assinaturas. O pagamento de "café" continua separado, via StoreKit direto, e está documentado em [docs/appstore/howto-storekit.md](../appstore/howto-storekit.md).

## Escopo

Este app usa dois modelos de monetização:

| Fluxo | Tecnologia | Produto | Código |
| --- | --- | --- | --- |
| Premium AI recorrente | RevenueCat + StoreKit 2 + App Store Connect | Assinaturas mensal/anual | `PremiumAccessStore` |
| Tip Jar | StoreKit 2 direto | `com.mneves.aipedometer.coffee` | `TipJarStore` |

Não use Apple Pay para o premium. Para conteúdo digital, assinatura e desbloqueio dentro do app, o caminho correto é In-App Purchase/App Store payments via StoreKit. Apple Pay é para outros tipos de transação, não para vender recursos digitais consumidos dentro do app.

## Decisões deste repo

- Bundle ID iOS: `com.mneves.aipedometer`
- Bundle ID watchOS: `com.mneves.aipedometer.watch`
- Bundle ID widgets: `com.mneves.aipedometer.widgets`
- Entitlement premium esperado: `premium`
- Offering recomendado: `default`
- Tip Jar: `com.mneves.aipedometer.coffee`
- SDK: `RevenueCat` e `RevenueCatUI` via Swift Package Manager
- StoreKit: StoreKit 2, com compras concluídas pela RevenueCat para o premium
- Login: o app não tem conta própria, então usa usuário anônimo da RevenueCat
- Segurança: se RevenueCat não estiver configurado, o app falha fechado e não libera AI premium

Arquivos principais:

- [project.yml](../../project.yml)
- [Config/Local.xcconfig.example](../../Config/Local.xcconfig.example)
- [AIPedometer/Resources/Info.plist](../../AIPedometer/Resources/Info.plist)
- [Shared/Constants/AppConstants.swift](../../Shared/Constants/AppConstants.swift)
- [AIPedometer/Core/Monetization/PremiumAccessStore.swift](../../AIPedometer/Core/Monetization/PremiumAccessStore.swift)
- [AIPedometer/Core/Monetization/PremiumAccessViews.swift](../../AIPedometer/Core/Monetization/PremiumAccessViews.swift)

## Ordem correta

Configure nesta ordem:

1. App Store Connect: contratos, banco, impostos e app record.
2. App Store Connect: produtos de assinatura.
3. App Store Connect: In-App Purchase Key e Issuer ID.
4. RevenueCat: app Apple, credenciais Apple, products, entitlement e offering.
5. Projeto local: `Config/Local.xcconfig`.
6. Device/TestFlight: sandbox purchase, restore, manage subscription e entitlement.
7. App Store Review: associar a assinatura à versão se for o primeiro IAP/subscription.

Não tente resolver primeiro pelo código. Se os produtos, entitlement, offering ou credenciais Apple estiverem errados, o app corretamente vai mostrar paywall vazio, estado indisponível ou premium bloqueado.

## 1. App Store Connect

### Contratos e acesso

Antes de criar ou testar produtos:

- aceite o Paid Apps Agreement;
- complete tax e banking;
- confirme que o app record existe;
- confirme que o bundle ID do app é `com.mneves.aipedometer`;
- confirme que a capability de In-App Purchase está disponível para o app;
- use uma conta com permissão suficiente para apps, IAP, subscriptions e keys.

Sem contratos, tax e banking em estado válido, a Apple pode ocultar opções de monetização ou bloquear testes.

### Produtos de assinatura

No App Store Connect:

1. Abra o app `AIPedometer`.
2. Vá para `Monetization` / `Subscriptions`.
3. Crie um subscription group para o premium.
4. Crie as assinaturas.

Modelo recomendado:

| Produto | Product ID sugerido | Duração |
| --- | --- | --- |
| AI Pedometer Premium Monthly | `com.mneves.aipedometer.premium.monthly` | 1 mês |
| AI Pedometer Premium Yearly | `com.mneves.aipedometer.premium.yearly` | 1 ano |

Regras importantes:

- Product ID é permanente depois de salvo.
- Não reutilize IDs deletados.
- Mantenha os IDs técnicos estáveis; mude texto comercial em metadata/paywall.
- Configure preço, disponibilidade, localizações e screenshot de review.
- Para subscription group com um único nível de acesso, mensal e anual devem representar o mesmo nível premium.

Metadata mínima:

| Campo | Recomendação |
| --- | --- |
| Reference Name | `AI Pedometer Premium Monthly`, `AI Pedometer Premium Yearly` |
| Display Name en-US | `AI Pedometer Premium` |
| Display Name pt-BR | `AI Pedometer Premium` |
| Description en-US | `AI insights, coach, plans, and reminders` |
| Description pt-BR | `Insights com IA, coach, planos e lembretes` |
| Review Notes | Explique onde abrir o paywall e como restaurar compras |
| Review Screenshot | Screenshot real do paywall ou tela premium |

### In-App Purchase Key

RevenueCat com iOS SDK 5+ e StoreKit 2 precisa da In-App Purchase Key para registrar transações corretamente.

No App Store Connect:

1. Abra `Users and Access`.
2. Abra `Integrations`.
3. Abra `In-App Purchase`.
4. Gere uma In-App Purchase Key.
5. Baixe o `.p8` uma única vez e guarde fora do repo.
6. Copie o `Issuer ID`.

Nunca commite `.p8`, issuer, private key ou credenciais ASC.

## 2. RevenueCat

### Criar app Apple

No dashboard da RevenueCat:

1. Crie ou abra o projeto do AIPedometer.
2. Adicione um app Apple/App Store.
3. Configure o bundle ID como `com.mneves.aipedometer`.
4. Confirme que o store/provider é Apple App Store.

### Subir credenciais Apple

Na configuração do app Apple dentro da RevenueCat:

1. Abra a área de App Store credentials.
2. Faça upload do `.p8` da In-App Purchase Key.
3. Preencha o `Issuer ID`.
4. Salve.
5. Rode a validação de credenciais até aparecer status válido.

Se a validação falhar, confira:

- bundle ID com casing correto;
- issuer ID correto;
- `.p8` correto;
- key ativa no App Store Connect;
- permissões da conta Apple.

### Importar products

No `Product catalog`:

1. Abra a aba Apple App Store.
2. Importe os produtos criados no App Store Connect.
3. Confira os identifiers:
   - `com.mneves.aipedometer.premium.monthly`
   - `com.mneves.aipedometer.premium.yearly`
4. Não crie identifiers diferentes na RevenueCat para o mesmo produto Apple.

### Criar entitlement

Crie um entitlement:

| Campo | Valor |
| --- | --- |
| Identifier | `premium` |
| Display name | `AI Pedometer Premium` |

Anexe ao entitlement todos os products que liberam premium:

- `com.mneves.aipedometer.premium.monthly`
- `com.mneves.aipedometer.premium.yearly`

O app lê exatamente `REVENUECAT_ENTITLEMENT_ID`; se você mudar de `premium` para outro valor, atualize o `Local.xcconfig` e qualquer ambiente de CI/release.

### Criar offering

Crie um offering:

| Campo | Valor recomendado |
| --- | --- |
| Identifier | `default` |
| Packages | `monthly`, `annual` |

Anexe cada package ao produto Apple correspondente.

O app usa esta regra:

- se `REVENUECAT_OFFERING_ID` estiver preenchido, busca esse offering;
- se estiver vazio, usa `currentOffering`.

Para produção, mantenha um offering `default` marcado como atual. Use offering customizado apenas para teste, experimento ou campanha controlada.

### Copiar public Apple API key

Na RevenueCat:

1. Abra `Project Settings`.
2. Abra `API Keys`.
3. Copie a chave pública Apple do app.

Essa chave começa normalmente com `appl_`. Ela vai para o client. Não use chave secreta privada no app.

## 3. Projeto local

Crie a configuração local:

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

`Config/Local.xcconfig` é local e ignorado pelo git. Não coloque chaves reais em `Config/Local.xcconfig.example`, `project.yml`, `Info.plist`, README ou docs.

Como os valores chegam ao app:

1. `Debug.xcconfig` e `Release.xcconfig` incluem `Local.xcconfig` quando ele existe.
2. `Info.plist` recebe `RevenueCatAPIKey`, `RevenueCatEntitlementID` e `RevenueCatOfferingID`.
3. `AppConstants.RevenueCat.resolveConfiguration()` ignora placeholders e resolve env vars/Info.plist.
4. `PremiumAccessStore.prepare()` configura a RevenueCat e busca `CustomerInfo`/`Offerings`.

Se `REVENUECAT_API_KEY` estiver ausente ou ainda for placeholder, `PremiumAccessStore` entra em `notConfigured` e a UI mostra assinaturas indisponíveis.

## 4. Código já implementado

O app configura RevenueCat assim:

- `Purchases.logLevel = .debug` em `DEBUG`;
- `Configuration.Builder(withAPIKey:)`;
- `purchasesAreCompletedBy: .revenueCat`;
- `storeKitVersion: .storeKit2`;
- `entitlementVerificationMode: .informational`;
- `Purchases.shared.offerings()`;
- `Purchases.shared.customerInfo()`;
- `Purchases.shared.purchase(package:)`;
- `Purchases.shared.restorePurchases()`;
- `Purchases.shared.syncPurchases()`;
- `Purchases.shared.customerInfoStream`;
- `RevenueCatUI.PaywallView(offering:)` apenas quando o offering tem Paywall v2 publicado (`Offering.hasPaywall == true`);
- fallback nativo do app quando o offering tem packages mas não tem Paywall v2 publicado;
- `showManageSubscriptions()` com fallback para `managementURL`.

Acesso premium é verdadeiro quando:

- o entitlement configurado está ativo no `CustomerInfo`; ou
- existe uma assinatura ativa conhecida vinculada aos packages carregados.

Se `CustomerInfo.entitlements.verification` retornar `.failed`, o app trata o resultado como não confiável e falha fechado, mesmo que o payload contenha entitlement ou produto premium ativo.

Não enfraqueça esse gate. Recurso AI premium deve continuar atrás de `premiumAccessStore.canAccessAIFeatures`.

## 5. Testes

### Teste rápido de UI sem loja

Use overrides para testar layout e gates:

```bash
-force-premium-on
-force-premium-off
PREMIUM_ENABLED=1
PREMIUM_ENABLED=0
```

Isso não valida Apple payments nem RevenueCat. Serve só para UI, snapshots e regressão local. Funciona apenas em builds Debug: builds Release ignoram esses overrides por segurança.

### RevenueCat Test Store

Use a Test Store da RevenueCat para desenvolvimento inicial quando os produtos Apple ainda não estiverem prontos.

Cuidados:

- não publique Release/TestFlight final com chave de Test Store;
- não trate Test Store como prova de App Store payments;
- valide produção com Apple Sandbox ou TestFlight.

### Apple Sandbox em device

No App Store Connect:

1. Abra `Users and Access`.
2. Abra `Sandbox`.
3. Crie um Sandbox Apple Account.
4. Use um email que nunca tenha sido usado como Apple Account real.
5. Escolha o país/região de teste.

No device:

1. Habilite Developer Mode.
2. Instale build development ou TestFlight.
3. Entre com o Sandbox Apple Account quando o fluxo de compra pedir.
4. Teste compra, restore, cancelamento, renovação e troca de plano.

Apple pode demorar até cerca de 1 hora para propagar mudanças de metadata/produtos no sandbox. Se acabou de criar ou editar produto, considere esse atraso antes de diagnosticar código.

### TestFlight

Para um passe de release real:

```bash
bash Scripts/test-payments-device.sh
```

O script valida auth local do `asc`, encontra o app por bundle ID, prepara IPA Release, cria/usa grupo TestFlight e orienta o fluxo de sandbox tester. Ele exige credenciais ASC configuradas fora do repo.

Também é útil rodar antes:

```bash
asc doctor
asc auth status
bash Scripts/verify-entitlements.sh
```

### Checklist obrigatório

- [ ] `REVENUECAT_API_KEY` pública Apple configurada.
- [ ] App abre sem estado `notConfigured`.
- [ ] `CustomerInfo` carrega.
- [ ] `Offerings` carrega.
- [ ] `currentOffering` ou `REVENUECAT_OFFERING_ID` retorna packages.
- [ ] Paywall mostra mensal e anual.
- [ ] Compra mensal ativa entitlement `premium`.
- [ ] Compra anual ativa entitlement `premium`.
- [ ] Restore reativa entitlement.
- [ ] Manage Subscription abre.
- [ ] Usuário sem assinatura vê gates fechados.
- [ ] Usuário com assinatura acessa AI Insights, AI Coach, Training Plans, Smart Reminders e Workouts AI.
- [ ] Tip Jar continua separado e não ativa premium.

## 6. App Store Review

Antes de enviar para review:

- produtos Apple estão em estado pronto para submissão;
- subscription group tem localizações;
- cada subscription tem preço, duração, localizações e screenshot de review;
- paywall do app mostra os produtos reais;
- review notes explicam onde encontrar o paywall;
- privacidade/metadata do app não promete recurso que não aparece no build;
- build usa chave RevenueCat Apple real;
- primeiro IAP/subscription é submetido junto com uma nova versão do app.

Se é a primeira assinatura/IAP do app, associe a subscription à versão na submissão da App Store. Esse detalhe costuma bloquear review quando esquecido.

Texto sugerido para review notes:

```text
Premium subscription is available from About > Premium and from AI feature gates in Dashboard, History, AI Coach, Training Plans, Workouts, and Smart Reminders. The app uses RevenueCat with StoreKit 2. Restore Purchases and Manage Subscription are available from About > Premium.
```

## 7. Troubleshooting

### Paywall abre sem produtos

Verifique:

- products importados na RevenueCat;
- products anexados ao entitlement `premium`;
- packages criados no offering;
- `default` marcado como current offering;
- `REVENUECAT_OFFERING_ID` não aponta para offering inexistente;
- produtos Apple propagaram para sandbox.

### Compra conclui mas premium não libera

Verifique:

- In-App Purchase Key válida na RevenueCat;
- product comprado anexado ao entitlement `premium`;
- app usa a public Apple API key correta;
- build não usa chave de Test Store por engano;
- `CustomerInfo.entitlements.active` contém `premium`;
- logs `premium.customer_info_failed`, `premium.offerings_failed`, `premium.purchase_failed`.

### App mostra assinaturas indisponíveis

Verifique:

- `Config/Local.xcconfig` existe;
- `REVENUECAT_API_KEY` não é `REVENUECAT_API_KEY`;
- `Info.plist` expandiu `RevenueCatAPIKey`;
- build foi regenerado após mudanças relevantes;
- `PremiumAccessStore.state` não está em `notConfigured`.

### Sandbox não mostra produto novo

Possíveis causas:

- metadata ainda propagando;
- Paid Apps Agreement/tax/banking incompletos;
- produto sem preço/localização;
- subscription group sem localização;
- Sandbox Apple Account com storefront errado;
- device ainda com cache de sandbox antigo.

### Review rejeita assinatura

Verifique:

- subscription foi associada à versão do app;
- screenshot de review existe;
- review notes explicam o fluxo;
- build acessa paywall sem conta/login especial;
- produtos aparecem em sandbox/TestFlight;
- todos os metadados obrigatórios estão completos.

## 8. Checklist go-live

- [ ] Paid Apps Agreement aceito.
- [ ] Tax e banking completos.
- [ ] Bundle ID Apple bate com `com.mneves.aipedometer`.
- [ ] Products mensal/anual criados no App Store Connect.
- [ ] In-App Purchase Key `.p8` gerada e guardada fora do repo.
- [ ] Issuer ID copiado.
- [ ] App Apple criado na RevenueCat.
- [ ] Credenciais Apple válidas na RevenueCat.
- [ ] Products Apple importados na RevenueCat.
- [ ] Entitlement `premium` criado.
- [ ] Products anexados ao entitlement.
- [ ] Offering `default` criado e com packages.
- [ ] Paywall v2 publicado para o offering se a intenção for usar o editor visual da RevenueCat; sem isso, o app usa o fallback nativo próprio.
- [ ] Public Apple API key colocada em `Config/Local.xcconfig` ou CI seguro.
- [ ] Build Release/TestFlight validado.
- [ ] Compra, restore e manage subscription testados.
- [ ] Primeiro IAP/subscription associado à versão na review.
- [ ] Tip Jar validado separadamente.

## Referências oficiais

- RevenueCat - Configuring Products: https://www.revenuecat.com/docs/projects/configuring-products
- RevenueCat - iOS Product Setup: https://www.revenuecat.com/docs/getting-started/entitlements/ios-products
- RevenueCat - In-App Purchase Key Configuration: https://www.revenuecat.com/docs/service-credentials/itunesconnect-app-specific-shared-secret/in-app-purchase-key-configuration
- Apple - Overview for configuring In-App Purchases: https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/overview-for-configuring-in-app-purchases
- Apple - In-App Purchase information: https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-information
- Apple - Auto-renewable subscription information: https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/auto-renewable-subscription-information
- Apple - Create a Sandbox Apple Account: https://developer.apple.com/help/app-store-connect/test-in-app-purchases/create-a-sandbox-apple-account/
- Apple - Testing In-App Purchases with sandbox: https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox
