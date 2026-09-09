# Redesign visual 2026 — registro de direção (ciclo 2026-06-12)

Registro histórico do ciclo de redesign iniciado em 2026-06-12 sobre a base `87f8045`
(0.89 / build 45) e fechado em 0.90 (46). O `CHANGELOG.md` cita este arquivo como o
registro da direção de design. Não é tracking vivo: o estado atual do repositório está
em `project.yml`, `CHANGELOG.md` e `MEMORY.md`. Os bloqueios de toolchain descritos na
época (runtime watchOS ausente, actool do watch) foram resolvidos e removidos deste
registro; a entrega para TestFlight e App Store continua aberta por configuração e
credenciais, conforme `MEMORY.md`.

## Direção de design adotada

Fontes: tendências de mobile UI/UX 2026 e os guias de Liquid Glass do iOS 26
(`glassEffect` / `GlassEffectContainer` / `glassEffectID`).

- **Liquid Glass como material vivo, não decoração**: morphing entre superfícies com
  `glassEffectID` e glass interativo em elementos tocáveis, evoluindo `GlassModifiers.swift`.
- **Motion narrativo, não gratuito**: animação curta, com gatilho claro e fácil de pular.
  `scrollTransition` para profundidade, `phaseAnimator` para estados vivos,
  `keyframeAnimator` para celebrações.
- **Kinetic typography**: `contentTransition(.numericText())` nos contadores — o coração
  de um pedômetro é o número.
- **Profundidade espacial**: camadas com parallax sutil via `visualEffect`.
- **Microinterações com feedback físico**: `sensoryFeedback` e `symbolEffect` em ícones
  de stats e ações.
- **Minimalismo com espaço negativo**: paleta contida (mint→cyan é a identidade),
  tipografia rounded para hero numbers.
- **Acessibilidade primeiro**: todo motion atrás de `motionAwareAnimation` /
  `accessibilityReduceMotion`, com Dynamic Type preservado.

## O que o ciclo entregou

- `Shared/DesignSystem/MotionEffects.swift`: tokens de motion (breath, celebration,
  stagger) e modifiers reduce-motion-aware (`breathingGlow`, `goalCelebration`,
  `scrollFadeIn`, `staggeredReveal`).
- Dashboard: anel com gradiente vivo, breathing glow, tip dot, staggered reveal nos stats
  e `sensoryFeedback` de milestone.
- History e Badges: barras com gradiente no goal-met, peak dot e confete determinístico
  (`ConfettiView`, via `Canvas` + `TimelineView`, que não renderiza nada sob Reduce Motion).
- Um easter egg local no Dashboard, documentado apenas no código.

## Lições do ciclo que continuam valendo

- `scrollFadeIn` com `.offset` movia o frame de acessibilidade e empurrou um CTA para
  baixo da tab bar. O deslocamento foi removido e o efeito é no-op sob UI testing:
  motion que altera geometria precisa de prova em XCUITest, não só visual.
- O bug de overflow de 32 bits do `ConfettiView` só apareceu no build de device, porque
  `Shared/` compila para `arm64_32`. Ver [FOR_YOU_KNOW.md](../../FOR_YOU_KNOW.md).

## Backlog remanescente

O refactor de arquitetura (F4) não foi concluído. Os itens abertos, com os números
atuais, estão em [codex-spec-f4.md](codex-spec-f4.md).
