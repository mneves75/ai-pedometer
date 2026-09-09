# Backlog F4 — decomposição de views e serviços

Backlog aberto, originado da spec escrita no ciclo 2026-06-12. Não é um despacho ativo:
nenhum agente deve executá-lo sem pedido explícito do usuário. Contexto do ciclo em
[refactor-ai-pedometer.md](refactor-ai-pedometer.md).

As regras de ambiente, os invariantes de concorrência, o premium fail-closed, a localização
e os design tokens **não são repetidos aqui**: [AGENTS.md](../../AGENTS.md) e
[docs/agents/](../agents/) são os donos dessas regras. Ler também [MEMORY.md](../../MEMORY.md)
e [FOR_YOU_KNOW.md](../../FOR_YOU_KNOW.md) antes de mover código com comportamento — em
particular o padrão `nonisolated static makeXCallback(continuation:)` para callbacks de
frameworks C/ObjC sem `@Sendable`, cuja referência é o `MotionService`.

## Situação (revisada em 2026-09-09)

Os três alvos cresceram desde a spec original; nenhuma decomposição foi feita.

| Alvo | Linhas na spec (2026-06) | Linhas hoje |
| --- | --- | --- |
| `AIPedometer/Features/Workouts/WorkoutsView.swift` | ~850 | 997 |
| `AIPedometer/Features/Settings/SettingsView.swift` | ~780 | 902 |
| `AIPedometer/Core/AI/Services/InsightService.swift` | 911 | 978 |

## Itens abertos

### 1. Decompor `WorkoutsView`

Extrair subviews privadas para arquivos próprios sob `Features/Workouts/Components/`
(header, banner ativo, toggle de expedição, card de Routes & GPX, seção de planos de treino,
carrossel recente); a recomendação de IA já vive em `Components/AIWorkoutCard.swift`. Lógica
não-UI já tem dono: o ingest de arquivo pertence a `GPXRouteImporter` e a projeção do plano
ativo a `TrainingPlanRecord` — a view apenas consome. Manter o `@Query` bounded como está.
Zero mudança visual.

### 2. Decompor `SettingsView`

Extrair as sections para `Features/Settings/Sections/` (editor de meta, modos de
rastreamento, notificações e lembretes inteligentes, sincronização de saúde, sobre/debug),
concentrando os efeitos colaterais no ponto que já existe (`SettingsSideEffects`).

### 3. Dividir `InsightService`

Separar por responsabilidade mantendo a fachada pública estável, para que as views não
mudem: daily insight, weekly analysis e workout recommendation podem virar colaboradores
internos. Preservar o cache com invalidação por dia, o gate `isStale` do snapshot
compartilhado (reproducer `dailyInsightIgnoresStaleSharedData`), o voo único por geração
descrito em FOR_YOU_KNOW.md e as instruções anti-claims-médicos. Rodar a suíte de IA inteira
depois do split.

## Itens fechados ou incorretos

- **`WidgetDataProvider` → seam compartilhado** (2026-07-13): a leitura passa por
  `SharedStepDataPersistence` em vez de decodificar o payload na própria view. O provider
  ainda constrói `UserDefaults(suiteName:)` inline; usar o acessor `UserDefaults.appGroup`
  seria uma limpeza menor, não um item de refactor.
- **Gaps de teste de `NotificationService` e `BackgroundTaskService`**: a premissa da spec
  estava errada. `AIPedometerTests/Notifications/NotificationServiceTests.swift` e
  `AIPedometerTests/Background/BackgroundTaskServiceTests.swift` já existiam antes dela.
- **Ainda aberto do item 5**: os modelos de persistência não têm testes de round-trip.
  `AIPedometerTests/Persistence/` só cobre migração e seleção de store.

## Restrição herdada

Não reescrever testes estáveis existentes: `BackgroundTaskServiceTests`,
`CoachServiceStreamingTests` e `TipJarStoreTests` foram deliberadamente mantidos como estão
desde o ciclo 0.87.

## Protocolo por item

Garantir teste cobrindo o comportamento antes de movê-lo (escrever primeiro se faltar),
refatorar, rodar a suíte unitária conforme [docs/agents/testing.md](../agents/testing.md),
e commitar por item com escopo explícito. Critério de done por item: comportamento
observável idêntico, suíte verde com testes realmente executados, e nenhuma view acima de
400 linhas nos diretórios tocados.
