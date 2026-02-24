# How To: StoreKit (Tip Jar "Café") no App Store Connect

Este guia descreve como colocar o pagamento de café em produção no App Store.

## 1. Pré-requisitos no App Store Connect

1. Entre com conta **Account Holder**.
2. Aceite o **Paid Apps Agreement**.
3. Preencha dados de **banco, impostos e informações legais**.

Sem isso, o IAP não pode ser publicado.

## 2. Escolha do tipo de produto

Para “me pague um café”, use normalmente:

- **Consumable**: permite comprar várias vezes (recomendado para gorjeta).

Use **Non-Consumable** apenas se a ideia for pagar uma vez e desbloquear algo permanente.

## 3. Criar o IAP no App Store Connect

1. App Store Connect → **Apps** → seu app.
2. Vá em **Monetization** → **In-App Purchases**.
3. Clique em `+` e escolha **Consumable**.
4. Defina o Product ID exatamente como no app:

`com.mneves.aipedometer.coffee`

## 4. Preencher metadados obrigatórios

Preencha para o IAP:

- Nome e descrição localizados (pt-BR e en).
- Preço (price tier).
- Disponibilidade por território.
- Screenshot (se exigido no fluxo atual da Apple).
- Review notes claras para o reviewer.

## 5. Alinhamento com o app (já implementado no projeto)

No projeto atual já existe:

- Product ID centralizado em `Shared/Constants/AppConstants.swift`.
- Compra via StoreKit 2 (`Product.products`, `purchase()`).
- Verificação de transação.
- Finalização de transação com `transaction.finish()`.
- Listener para `Transaction.unfinished` e `Transaction.updates`.

## 6. Testes antes da submissão

### 6.1 Local (Xcode + StoreKit Configuration)

- Use `StoreKit/TipJar.storekit`.
- Rode pelo Xcode (`Cmd+R`) para testes locais.

### 6.2 Sandbox/TestFlight (fluxo real)

1. Crie conta de **Sandbox Tester**.
2. Teste no TestFlight:
   - compra aprovada;
   - cancelamento;
   - compra pendente;
   - repetição de compra (consumable).
3. Valide logs e UI para erro de indisponibilidade.

## 7. Regra de submissão do IAP

- Se for o **primeiro IAP do app**, envie junto com uma nova versão do app.
- Depois de aprovado ao menos um IAP, novos IAPs podem ser submetidos separadamente (quando permitido pelo fluxo atual).

## 8. Publicação

1. Envie build com versão atual.
2. Associe o IAP na submissão.
3. Aguarde review.
4. Após aprovado:
   - mantenha “Cleared for Sale” ativo;
   - confirme territórios ativos;
   - valide compra em produção.

## 9. Checklist rápido (go-live)

- [ ] Product ID igual no código e no ASC.
- [ ] IAP tipo **Consumable**.
- [ ] Agreements/Tax/Bank completos.
- [ ] Metadados/localizações completos.
- [ ] Testes em Sandbox/TestFlight validados.
- [ ] Build enviado com IAP associado (se primeiro IAP).
- [ ] IAP aprovado e “Cleared for Sale”.

## 10. Referências oficiais Apple

- https://developer.apple.com/help/app-store-connect/manage-agreements/sign-and-update-agreements/
- https://developer.apple.com/help/app-store-connect/manage-tax-information/provide-tax-information
- https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-consumable-or-non-consumable-in-app-purchases/
- https://developer.apple.com/help/app-store-connect/reference/in-app-purchase-information
- https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/set-a-price-for-an-in-app-purchase/
- https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase
- https://developer.apple.com/documentation/StoreKit/testing-in-app-purchases-with-sandbox
- https://developer.apple.com/help/app-store-connect/test-in-app-purchases/create-a-sandbox-apple-account/
- https://developer.apple.com/documentation/storekit/product
