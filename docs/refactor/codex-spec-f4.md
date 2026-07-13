# Spec F4 — Refactor de arquitetura (executor: Codex gpt-5.5 xhigh)

> Spec histórica criada pela sessão Claude (Fable 5) no ciclo 2026-06-12; não é
> um despacho ativo. Status reconciliado em 2026-07-13: o item 4 foi concluído no
> working tree local; os itens 1–3 e 5 continuam no backlog. Tracking geral em
> `docs/refactor/refactor-ai-pedometer.md`.

## Leitura obrigatória antes de começar

1. `CLAUDE.md` (raiz do repo) — contrato operacional completo.
2. `MEMORY.md` — decisões e landmines (especialmente: refreshChain, fail-closed premium, callbacks ObjC não-@Sendable).
3. `FOR_YOU_KNOW.md` — mapa mental do projeto.
4. `docs/agents/build-and-dev.md` e `docs/agents/testing.md`.

## Regras de ambiente (NÃO negociáveis)

- TODO build/test: `DEVELOPER_DIR=/Applications/Xcode.app xcodebuild ...` (o xcode-select aponta para o beta 27, que quebra RevenueCat em test builds).
- Destino: `platform=iOS Simulator,name=iPhone 17`, `-parallel-testing-enabled NO`.
- Novos arquivos Swift exigem `xcodegen generate` (e o postGen reescreve entitlements — nunca editar `.entitlements` direto).
- Swift 6.2 strict concurrency + warnings-as-errors (vale para test doubles também).
- `Executed 0 tests` NÃO é evidência. Seletores `-only-testing:` de Swift Testing precisam de `()` no nome da função.
- Não rodar dois xcodebuild simultâneos no mesmo destino.
- Strings de UI novas em `Shared/Resources/Localizable.xcstrings`; tokens de design (`DesignTokens.*`) em vez de literais (greps de enforcement: `\.frame(width: [0-9]` e `cornerRadius: [0-9]`).

## Invariantes de produto (qualquer violação = bug)

- Premium FAIL-CLOSED. Nenhum caminho novo de entitlement; nada de inferir premium de `isUITesting`/product ids.
- `StepTrackingService.refreshChain` (serialização run-to-completion de `refreshTodayData`) fica como está; NÃO converter para drop/coalesce.
- Comportamento observável idêntico: este ciclo é refactor estrutural, não mudança de feature.
- Callbacks de frameworks C/ObjC sem `@Sendable` chamados de contexto isolado: usar o padrão `nonisolated static makeXCallback(continuation:)` (ver `MotionService`).

## Escopo (em ordem; commits separados por item)

### 1. Decompor `AIPedometer/Features/Workouts/WorkoutsView.swift` (~850 linhas) — backlog

- Extrair subviews privadas em arquivos próprios sob `Features/Workouts/Components/` (header, active banner, AI recommendation, expedition toggle, Routes & GPX card, training plans section, recent carousel).
- Mover lógica não-UI para os seams existentes: import GPX já pertence a `GPXRouteImporter` (NÃO trazer ingest de arquivo de volta para a view); projeção de plano ativo já pertence a `TrainingPlanRecord` — a view só consome.
- Estado da view: manter `@Query` bounded (fetchLimit 6 + endTime != nil) como está.
- Meta: WorkoutsView < 300 linhas, zero mudança visual (verificar por screenshot antes/depois se possível).

### 2. Decompor `AIPedometer/Features/Settings/SettingsView.swift` (~780 linhas) — backlog

- Extrair sections em arquivos próprios (`Features/Settings/Sections/`): goal editor, tracking modes, notifications/smart reminders, health sync, about/debug.
- Consolidar os `Task { await trackingService.* }` espalhados em um ponto de side-effect por section (padrão já existente em `SettingsSideEffects`, se aplicável — verificar antes).

### 3. Dividir `AIPedometer/Core/AI/Services/InsightService.swift` (911 linhas) — backlog

- Separar por responsabilidade mantendo a fachada pública `InsightService` estável (views não mudam): geração de daily insight, weekly analysis e workout recommendation podem virar tipos internos/colaboradores.
- PRESERVAR: cache com invalidação por dia, gate `isStale` do snapshot compartilhado (fix do 0.87 — há reproducer `dailyInsightIgnoresStaleSharedData`), instruções anti-claims-médicos.
- Rodar a suíte de AI inteira após o split.

### 4. `AIPedometerWidgets/Shared/WidgetDataProvider.swift` → seam compartilhado — concluído localmente em 2026-07-13

- Hoje lê `UserDefaults(suiteName:)` direto; fazer consumir o mesmo seam de `SharedStepData`/`SharedDataStore` usado pelo app (mover o seam para `Shared/` se necessário).
- Cuidado com isolamento: widgets têm processo próprio; manter Sendable/concurrency limpos.

### 5. Gaps de teste (somente onde NÃO há cobertura) — backlog

- `NotificationService` (66L) e `BackgroundTaskService` (115L): testes de contrato básicos com fakes (autorização negada, agendamento idempotente).
- Persistence models sem suíte: testes de round-trip mínimos.
- NÃO reescrever testes estáveis existentes (BackgroundTaskServiceTests/CoachServiceStreamingTests/TipJarStoreTests foram deliberadamente deixados como estão no ciclo 0.87).

## Protocolo por item

1. Antes de mover código com comportamento: garantir que existe teste cobrindo o comportamento (escrever primeiro se faltar).
2. Refatorar.
3. `DEVELOPER_DIR=/Applications/Xcode.app xcodebuild -scheme AIPedometer -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO -only-testing:AIPedometerTests test` → verde com testes reais executados.
4. Commit convencional (`refactor: ...`) com escopo do item. NUNCA `git add -A` — stage só os arquivos do item.

## Critério de done

- Itens 1–5 commitados, suíte unitária completa verde, build dos targets Widgets e Watch verde
  (`xcodebuild -scheme AIPedometer ... build` já compila todos).
- Nenhuma view > 400 linhas em `Features/Workouts` e `Features/Settings`.
- `git status` limpo (sem arquivos órfãos não rastreados).
- Resumo final: o que mudou, evidência de teste por item, qualquer desvio justificado.
