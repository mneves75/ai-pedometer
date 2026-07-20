# Refactor & Redesign — ai-pedometer (registro do ciclo 2026-06-12)

Registro histórico do ciclo de redesign visual + review de arquitetura iniciado em 2026-06-12. Não é um tracking vivo; os status foram reconciliados em 2026-07-13 com o estado local do repositório.
Base: `87f8045` (0.89 / build 45), working tree limpo.

O repositório local está em `0.94 (50)`. Bloqueios de ambiente e deploy descritos no log abaixo
pertencem à sessão de junho e não comprovam o estado atual de TestFlight ou App Store Connect.

## Objetivos

1. **Redesign frontend** visualmente marcante e interativo, com motion effects e um easter egg escondido, alinhado às tendências 2026.
2. **Review completo** de arquitetura e código, com refactor até a arquitetura ficar satisfatória.
3. **Live test após cada passo significativo** (build + testes + verificação no simulador), autoreview e commit por fase.

## Direção de design 2026 (pesquisa 2026-06-12)

Fontes: tendências de mobile UI/UX 2026 (Tubik, Muzli, UX Pilot, MindInventory) e guias de Liquid Glass iOS 26 (SwiftUI `glassEffect`/`GlassEffectContainer`/`glassEffectID`).

Princípios adotados:

- **Liquid Glass como material vivo, não decoração**: morphing entre superfícies com `glassEffectID`, glass interativo em elementos tocáveis. O app já tem `GlassModifiers.swift` — evoluir, não substituir.
- **Motion narrativo, não gratuito**: animação curta, com gatilho claro e fácil de pular. `scrollTransition` para profundidade em listas/grids, `phaseAnimator` para estados vivos (ring no goal), `keyframeAnimator` para celebrações.
- **Kinetic typography**: números que rolam com `contentTransition(.numericText())` nos contadores de passos/stats — o coração de um pedômetro é o número.
- **Profundidade espacial**: camadas com parallax sutil via `visualEffect`, sombras/blur por hierarquia.
- **Microinterações com feedback físico**: `sensoryFeedback` + `symbolEffect` (bounce/pulse) nos ícones de stats e ações.
- **Minimalismo com espaço negativo**: paleta contida (mint→cyan já é a identidade), tipografia rounded para hero numbers.
- **Acessibilidade primeiro**: todo motion atrás de `motionAwareAnimation`/`accessibilityReduceMotion` (infra já existe em `ConditionalViewModifiers.swift`); Dynamic Type preservado.
- **Easter egg**: interação escondida, local, sem dados externos, reduce-motion-aware (detalhe em F2; não documentar o gatilho em strings de UI).

## Estado atual (inventário 2026-06-12)

- Design system maduro em `Shared/DesignSystem/` (tokens completos, glass modifiers, motion-aware modifiers, haptics).
- Motion atual é mínimo: 8 usos de `withAnimation`/`.animation`/`.transition` em Features; zero `phaseAnimator`, `keyframeAnimator`, `symbolEffect`, `sensoryFeedback`, `scrollTransition`, `Canvas`, `TimelineView`.
- Liquid Glass já aplicado em 10 arquivos via `.glassCard()`/`.glassMorphTransition()`.
- Nenhum easter egg existente.
- Produção: 126 arquivos Swift / ~19.9k linhas; testes: ~10.4k linhas (forte em services, zero em views).
- Hotspots de tamanho: InsightService 911L, WorkoutsView 853L, SettingsView 776L, StepTrackingService 775L, TrainingPlanService 720L.
- Views com lógica embutida: WorkoutsView (queries + GPX import + retry), SettingsView (handlers espalhados), DashboardView/HistoryView (load triggers + fallbacks).
- `WidgetDataProvider` lê UserDefaults direto em vez de reusar o seam compartilhado.

## Fases

| Fase | Escopo | Executor | Status | Evidência |
|------|--------|----------|--------|-----------|
| F0 | Baseline verde (build + unit tests + screenshots) | Claude (main) | concluído no ciclo | log de execução abaixo |
| F1 | Motion tokens v2 + Dashboard hero (ring vivo, kinetic numbers, scrollTransition, haptics) | Claude (main) | concluído no ciclo | suíte e screenshots registradas abaixo |
| F2 | History chart vivo + Badges celebration (partículas Canvas/TimelineView) + **easter egg** | Claude (main) | concluído no ciclo | implementação e verificação registradas abaixo |
| F3 | Onboarding/Workouts/Coach motion polish | Claude (main) | feito, verde | suíte 465 verde |
| F4 | Refactor arquitetura: decompor WorkoutsView/SettingsView, split InsightService, WidgetDataProvider→seam compartilhado, gaps de teste | Codex (/goal, gpt-5.5 xhigh) | parcial: item 4 concluído localmente em 2026-07-13; itens 1–3 e 5 em backlog | `docs/refactor/codex-spec-f4.md` |
| F5 | Fechamento: bump 0.90 (46), CHANGELOG, docs, autoreview, commit/push/tag, deploys | Claude (main) | parcial: ciclo local 0.90 fechado; deploys não comprovados | seções Fechamento e Deploys abaixo |

Regra por fase: build + testes relevantes verdes → verificação visual no simulador (argent) → autoreview → commit. Nenhuma fase fecha sem evidência.

## Decisões e restrições herdadas (NÃO violar)

- `DEVELOPER_DIR=/Applications/Xcode.app` em todo build/test (beta 27 quebra RevenueCat em test builds).
- DesignTokens obrigatórios: greps de enforcement `\.frame(width: [0-9]` e `cornerRadius: [0-9]`.
- Premium fail-closed; nada de novos caminhos de entitlement.
- `refreshChain` do StepTrackingService intocável (serialização run-to-completion).
- Strings novas em `Shared/Resources/Localizable.xcstrings`.
- Entitlements só via `Scripts/restore-entitlements.sh`.
- Novos arquivos Swift exigem `xcodegen generate`.
- Split do WorkoutsView foi deferido no ciclo 0.87 por risco pré-release; este ciclo o usuário pediu explicitamente refactor profundo → entra em F4 com cobertura de teste antes do split.

## Log de execução

### 2026-06-12

- Sessão iniciada. Leitura obrigatória completa, inventário frontend + mapa de arquitetura coletados por subagentes, tendências 2026 pesquisadas.
- F0: build de baseline **verde** após corrigir drift de runtime: não havia runtime watchOS 26.x instalado; `xcrun simctl runtime match set watchos26.5 24R5289n` resolveu ("watchOS 26.5 must be installed").
- F0: primeira rodada da suíte falhou por **timeout de boot do simulador** (infra, não teste). A recuperação custou caro — lições:
  - `killall -9 CoreSimulatorService` deixa sessões fantasma no SimLaunchHost ("Bad or unknown session") e dispara churn de recriação de device pairs; o device flapava Booted→Shutdown por minutos. Evitar o killall; preferir `simctl shutdown all` + paciência.
  - Daemons do sim crashando (CoreSimulatorBridge SIGABRT) com runtime override `iphoneos26.5 → 23F73` antigo; com o runtime 23F77 agora instalado, `runtime match set iphoneos26.5 23F77` + `simctl erase` do device estabilizou.
  - **Argent 0.7.0 está parcialmente quebrado nesta máquina**: `launch-app`/`screenshot`/`gesture-*` falham (simulator-server não sobe; injeção DYLD falha). `describe` (ax-service) FUNCIONA. Workflow de verificação visual adotado: `describe` (coordenadas) → `axe tap` (pontos 402×874 no iPhone 17) → `simctl io screenshot`. Update 0.11.0 disponível — avisar usuário.
- F0: screenshots de baseline capturados em `/tmp/aiped-baseline-shots/` (onboarding, dashboard, history, workouts, aicoach, more) — estados vazios (sem permissão Health no sim; demo mode via defaults não surtiu efeito visível).
- Spec F4 para Codex escrita em `docs/refactor/codex-spec-f4.md`.

#### BLOQUEIO DE AMBIENTE: build do watchOS impossível (runtime 26.x removido)

- O runtime watchOS 26.x foi **desinstalado** desta máquina; só resta watchOS 27.0. A Apple
  **não disponibiliza** nenhum watchOS 26.x para download (`xcodebuild -downloadPlatform watchOS`
  só oferece 27.0; 26.5/26.4/26.0 retornam "not available for download"). Sem dmg cacheado.
- O `actool` do watch usa `--filter-for-device-os-version 26.5` (versão do SDK do Xcode 26.6) e
  exige o device de thinning **Apple Watch Series 7 (45mm)**, que é incompatível com watchOS 27.0
  (`simctl create` falha com "Incompatible device"). O `runtime match set watchos26.5 → 27.0`
  redireciona o SDK mas NÃO muda a era do device que o actool escolhe → build do watch FALHA.
- Tentativas que NÃO resolvem: `WATCHOS_DEPLOYMENT_TARGET=27.0` (SDK continua 26.5), criar Series 9
  (45mm) na mesma geometria (actool fixa Series 7 literal), runtime match.
- O baseline build inicial passou só porque havia um device watchOS 26.5 **cacheado** no IB Support
  set; o `killall CoreSimulatorService` + `simctl erase` desta sessão o destruiu, expondo o drift.
- **Este bloqueio atinge o baseline commitado também**, não só o redesign. Verificação iOS feita
  removendo TEMPORARIAMENTE o target watch de `project.yml` (reversível via `git checkout project.yml`).
  O `project.yml` commitado MANTÉM o watch. AÇÃO PARA O USUÁRIO: reinstalar um runtime watchOS 26.x
  (via Xcode beta com SDK 27, ou aguardar a Apple republicar) para destravar build/test do watch.

#### F1 — Motion tokens v2 + Dashboard hero (feito, verde)

- Novo `Shared/DesignSystem/MotionEffects.swift`: tokens de motion (breath/celebration/stagger) +
  modifiers reduce-motion-aware: `breathingGlow` (phaseAnimator), `goalCelebration` (pop no goal),
  `scrollFadeIn` (scrollTransition), `staggeredReveal` (entrada escalonada).
- Dashboard: ring com gradiente vivo mint→cyan→accent + breathing glow + tip dot luminoso na ponta
  do arco; números já com `contentTransition(.numericText)`; stats grid com staggered reveal +
  scrollFade; `sensoryFeedback` de milestone (25/50/75%) e success no goal.
- Lógica pura `DashboardView.milestoneBucket(progress:)` + 3 testes (table 11 casos, guarda
  não-positivo, monotonicidade) — todos verdes.
- Evidência: suíte unitária 465 testes, só a falha de localização pt-BR pré-existente (ver abaixo).

#### F2 — History chart vivo + Badges celebration + EASTER EGG (concluído no ciclo)

- `Shared/DesignSystem/ConfettiView.swift`: confete via `Canvas` + `TimelineView`, partículas
  determinísticas (jitter por índice, sem `Math.random`), reduce-motion-aware (renderiza nada).
- History: `BarChartColumn` com gradiente mint→cyan no goal-met + peak dot + breathing glow;
  history rows com scrollFade + numericText.
- Badges: ícone de celebração com breathing glow + **confete** na BadgeCelebrationSheet.
- **EASTER EGG**: 7 toques no centro do anel de progresso do Dashboard disparam um confete secreto
  + haptic de sucesso. Sem dica de UI, 100% local, reduce-motion-aware. (Não documentar o gatilho
  em strings de UI — está só aqui e no código.)

#### Falha de teste PRÉ-EXISTENTE (não é regressão do redesign)

- `LocalizationTests/partialResponseNoticesAreTranslatedInPortugueseBrazil()` falhava (2 assertions)
  neste ciclo; o teste foi corrigido localmente em 2026-07-13 para carregar explicitamente o bundle pt-BR.
- Prova de pré-existência: `git diff HEAD` do teste E de `Localizable.xcstrings` está **vazio**; o
  `.app` compilado **contém** a tradução pt-BR correta (`pt-BR.lproj/Localizable.strings`).
- Causa: `String(localized:locale:)` no Xcode 26.6 não força a seleção da tabela pt-BR via o
  parâmetro `locale:` (só afeta formatação de interpolação); precisaria de `bundle:` + processo em
  pt-BR. Bug do teste/ambiente, independente do redesign.

#### F3 — Onboarding/Workouts/Coach (feito, verde)

- Onboarding: hero icon com breathingGlow + symbolEffect bounce; número da meta com
  `contentTransition(.numericText)` ao mover o slider.
- Workouts: cada section com `scrollFadeIn`.
- AICoach: mensagens entram com `move(edge:.bottom)+opacity` (reduce-motion → só opacity),
  container anima em `messages.count`.
- Autocrítica aplicada: removido o `breathingGlow` por-barra no History (até 7 glows pulsando =
  ruído visual + custo); mantido só o peak dot com glow estático.
- Evidência: suíte 465 testes verde (só a falha pt-BR pré-existente). Build linka limpo.

#### Autoreview (Codex) — 1 achado, resolvido

- Único achado [P2]: `project.yml` sem o target `AIPedometerWatch` — era o workaround LOCAL para
  buildar sem o watch (bloqueio de runtime). Restaurado antes do commit; re-review confirma limpo.
- O resto do redesign passou sem achados acionáveis.

#### Fechamento (F5)

- Bump `0.90 (46)` em `project.yml` (watch restaurado primeiro), `xcodegen generate` re-rodado.
- CHANGELOG `[0.90]` + bump de versão em README/test_plan/docs de agentes/playbook ASC.
- Nota durável sobre os motion modifiers adicionada ao `CLAUDE.md` do projeto.
- Verificação visual: app lança/navega limpo no sim dedicado (onboarding + dashboard íntegros, sem
  crash). O anel com gradiente/tip/glow só aparece com passos > 0 (guarda correta); injeção de
  dados HealthKit no sim não disponível sem sample data, então o estado data-rico não foi
  fotografado — mas o código compila e a suíte cobre a lógica de milestone.
- AMBIENTE: simulador instável + DISPUTADO por uma sessão paralela (outro app "Paquera", sims
  SV-Redesign/AIR-Redesign/CV-TestRunner/AIR-RD3 não criados por mim) que derruba meus simuladores
  (SIGKILL 137 em test runs). Capturas exigiram sim dedicado e retries.

### Segunda passada (atendendo "do it all / try everything")

- **autoreview (Codex) rodou até limpo** (3 ciclos): achou (1) remoção temp do watch no project.yml
  [restaurado], (2) numericText do StatCard sem gate de Reduce Motion [gateado], (3) TimelineView do
  ConfettiView a 60fps após o burst [pausado com `isFinished`]. Re-review final: "patch is correct".
- **Bug REAL pego pelo build de DEVICE (não pelo sim nem pelo autoreview):** `ConfettiView` em
  `Shared/` compila no watchOS (arm64_32, Int 32-bit); a constante de Knuth `2_654_435_761` estoura
  Int32. Fix: aritmética `UInt32` com wrapping. Commit `77879fb`.
- **e2e (XCUITests) pegou 2 regressões REAIS do redesign:** o `scrollFadeIn` deixava o CTA "Iniciar
  treino" do Workouts sob a tab bar (`assertWorkoutsLoaded`, y≈855 > 792). Fix: removido o `.offset`
  do `scrollFadeIn` (movia o frame de acessibilidade/hit-test) + tornado no-op sob UI testing +
  removido o scrollFadeIn dos sections do Workouts (Dashboard/History mantêm, passam no e2e). Commit
  `4a57f11`. A suíte XCUITest completa NÃO pôde ser confirmada 100% verde nesta sessão por causa da
  contenção severa (SIGKILL 137 + flake `tab_workouts`-not-found, classe documentada no MEMORY) —
  re-rodar em máquina ociosa.

### Deploys (tentados, com erros exatos capturados)

- **App record EXISTE no ASC** (ID `6778785816`→ na verdade `6778799265`, "AIPedometer - aipedometer").
  A nota de 2026-06-10 de que não existia está obsoleta. `asc doctor` ok.
- **BLOQUEIO de toolchain pincer** impede QUALQUER build distribuível com o watch:
  - Xcode 26.6: `xcodebuild archive` falha no actool do watch (runtime watchOS 26.x removido).
  - Xcode 27 beta: archive falha no RevenueCat sob Swift 6.4 (`PaywallColor`/`CustomerCenterConfigData`).
  - → **staging (TestFlight), prod (App Store) e iMarcus** todos bloqueados igualmente.
- **iMarcus**: device conectado (iPhone 17 Pro Max) + Apple Watch Ultra 2 pareado; o build falhou —
  PRIMEIRO no bug de 32-bit do ConfettiView (corrigido), e em seguida cairia no mesmo actool do watch.
- **Unblock recomendado (decisão do usuário):** (a) restaurar runtime watchOS 26.x (fora do controle —
  Apple não disponibiliza), OU (b) bumpar o RevenueCat para revisão compatível com Swift 6.4 e
  arquivar com o Xcode 27 beta. (b) é revenue-critical → NÃO feito autonomamente.

### F4 (refactor de arquitetura) — status reconciliado em 2026-07-13

- A spec histórica permanece em `docs/refactor/codex-spec-f4.md`; ela não representa um despacho ativo.
- O item 4 (`WidgetDataProvider` → seam compartilhado) foi implementado no working tree local em
  2026-07-13. Os itens 1–3 e 5 continuam no backlog e não devem ser inferidos como concluídos.
