// Real-model evaluation of the AI Coach fix (2026-09-24), run on a Mac with Apple Intelligence:
//   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
//     swift Scripts/coach-grounding-eval.swift <runs> <report.md>
//
// Replays the owner's conversation from the device screenshots ("Crie um plano para alcançar 10.000
// passos", then "Pesquise no app health") against the on-device model in two conditions:
//   A  1.0.8 (66): instructions from commit 426e3f7, `days` required, no data sent with the turn.
//   B  1.0.8 (67): instructions from the working tree, `days` optional, first turn grounded.
// Both conditions get tools that return the same fixture data, so condition A can still succeed by
// calling the tool. A turn "asks the user" when it requests activity data or claims it cannot access
// Apple Health; it "uses data" when it quotes a fixture step count.
import Foundation
import FoundationModels

let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let runs = CommandLine.arguments.count > 1 ? Int(CommandLine.arguments[1]) ?? 8 : 8
let reportPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "coach-grounding-report.md"
let languageInstruction = "Respond in the user's app language: português (Brasil) (pt-BR)."

func shell(_ args: [String]) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = args
    process.currentDirectoryURL = repo
    let pipe = Pipe()
    process.standardOutput = pipe
    try? process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
}

/// The literal inside `coachInstructions`, with Swift's multi-line indentation stripped.
func coachInstructions(fromSource source: String) -> String {
    guard let function = source.range(of: "static func coachInstructions("),
          let open = source.range(of: "\"\"\"\n", range: function.upperBound..<source.endIndex),
          let close = source.range(of: "\"\"\"", range: open.upperBound..<source.endIndex)
    else { fatalError("coachInstructions literal not found") }
    return source[open.upperBound..<close.lowerBound]
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { $0.hasPrefix("        ") ? String($0.dropFirst(8)) : String($0) }
        .joined(separator: "\n")
        .replacingOccurrences(of: "\\(languageInstruction)", with: languageInstruction)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

let oldInstructions = coachInstructions(fromSource: shell(["git", "show", "426e3f7:AIPedometer/Core/AI/Services/CoachService.swift"]))
let newInstructions = coachInstructions(fromSource: (try? String(contentsOf: repo.appendingPathComponent("AIPedometer/Core/AI/Services/CoachService.swift"), encoding: .utf8)) ?? "")

let fixtureSteps = [6_850, 4_120, 8_930, 11_240, 5_310, 7_760, 3_980]
let fixtureStepText = ["6.850", "4.120", "8.930", "11.240", "5.310", "7.760", "3.980"]
let fixtureAverageText = "6.884" // 48.190 / 7
let activityFixture: String = {
    let days = ["18 de set. de 2026", "19 de set. de 2026", "20 de set. de 2026", "21 de set. de 2026",
                "22 de set. de 2026", "23 de set. de 2026", "24 de set. de 2026"]
    let summary = "Últimos 7 dias: total de 48.190 passos, média diária de \(fixtureAverageText) passos, meta alcançada em 1 deles"
    return summary + "\n---\n" + zip(days, zip(fixtureSteps, fixtureStepText)).map { day, pair in
        let (steps, text) = pair
        return """
        Data: \(day)
        Passos: \(text)
        Distância: \(String(format: "%.1f", Double(steps) * 0.72 / 1000).replacingOccurrences(of: ".", with: ",")) km
        Andares: 2
        Calorias: \(steps / 30) kcal
        Meta: 10.000 passos
        Status: \(steps >= 10_000 ? "Meta Alcançada" : "Meta Não Alcançada")
        """
    }.joined(separator: "\n---\n")
}()
let goalFixture = "Meta diária atual: 10.000 passos"
let streakFixture = "Sequência atual: 0 dias"

final class ToolCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func record() { lock.lock(); count += 1; lock.unlock() }
    func take() -> Int { lock.lock(); defer { count = 0; lock.unlock() }; return count }
}
let toolCalls = ToolCalls()

struct OldActivityTool: Tool {
    let name = "fetchActivityData"
    let description = "Fetches user's step count, distance, floors, and activity data for a specified number of days"
    @Generable struct Arguments {
        @Guide(description: "Number of days to fetch data for, between 1 and 90", .range(1...90))
        let days: Int
    }
    func call(arguments: Arguments) async throws -> String { toolCalls.record(); return activityFixture }
}

struct NewActivityTool: Tool {
    let name = "fetchActivityData"
    let description = "Fetches user's step count, distance, floors, and activity data for a specified number of days"
    @Generable struct Arguments {
        @Guide(description: "Past days to fetch, 1 to 90. Omit for the last 7 days.", .range(1...90))
        let days: Int?
    }
    func call(arguments: Arguments) async throws -> String { toolCalls.record(); return activityFixture }
}

struct GoalTool: Tool {
    let name = "fetchGoalData"
    let description = "Fetches user's current daily step goal"
    @Generable struct Arguments {}
    func call(arguments: Arguments) async throws -> String { toolCalls.record(); return goalFixture }
}

struct StreakTool: Tool {
    let name = "fetchStreakData"
    let description = "Fetches user's current streak information"
    @Generable struct Arguments {}
    func call(arguments: Arguments) async throws -> String { toolCalls.record(); return streakFixture }
}

let askPattern = #/(?i)(quantos dias|quantos passos|poderia me (informar|dizer)|pode me (informar|dizer)|me (diga|informe|conte)|compartilh|n[ãa]o (consigo|posso|tenho como) (acessar|pesquisar|buscar|consultar)|n[ãa]o permite|n[ãa]o tenho acesso|forne[çc]a)/#

// The prompt scaffolding is English; a pt-BR answer that echoes it or slips into English is a defect.
let englishPattern = #/(Activity data|Apple Health data|User message|read by the app|\b(Your|the|with|days|Other|Current streak|Daily step goal|Keep|Great)\b)/#

// Any "média ... N" whose N is not the true 7-day average (6.884) is a miscalculation.
let averagePattern = #/(?i)m[ée]dia[^0-9\n]{0,40}([0-9]{1,2}\.[0-9]{3})/#

func wrongAverage(_ text: String) -> Bool {
    text.matches(of: averagePattern).contains { match in
        match.output.1 != Substring(fixtureAverageText)
    }
}

func classify(_ text: String) -> (asks: Bool, usesData: Bool, english: Bool) {
    (text.contains(askPattern), fixtureStepText.contains { text.contains($0) } || text.contains(fixtureAverageText), text.contains(englishPattern))
}

struct Turn { let prompt: String; let response: String; let toolCalls: Int; let asks: Bool; let usesData: Bool; let english: Bool; var miscalculated: Bool { wrongAverage(response) } }

func runConversation(grounded: Bool) async -> [Turn] {
    let session = grounded
        ? LanguageModelSession(tools: [NewActivityTool(), GoalTool(), StreakTool()], instructions: newInstructions)
        : LanguageModelSession(tools: [OldActivityTool(), GoalTool(), StreakTool()], instructions: oldInstructions)
    let messages = ["Crie um plano para alcançar 10.000 passos", "Pesquise no app health"]
    var turns: [Turn] = []
    for (index, message) in messages.enumerated() {
        var prompt = message
        // Same rule as `CoachService`: the first turn, and any turn that asks about Apple Health.
        if grounded && (index == 0 || message.contains(#/(?i)\b(sa[úu]de|health|healthkit)\b/#)) {
            // Same shape as `CoachService.groundedPrompt` with its pt-BR headings.
            prompt = """
            Seus dados do app Saúde, lidos agora pelo app (\(Date().formatted(date: .complete, time: .shortened))):
            \(activityFixture)
            \(goalFixture)
            \(streakFixture)

            Mensagem do usuário:
            \(message)
            """
        }
        _ = toolCalls.take()
        let text: String
        do { text = try await session.respond(to: prompt).content } catch { text = "ERROR: \(error)" }
        let verdict = classify(text)
        turns.append(Turn(prompt: message, response: text, toolCalls: toolCalls.take(), asks: verdict.asks, usesData: verdict.usesData, english: verdict.english))
    }
    return turns
}

guard case .available = SystemLanguageModel.default.availability else {
    print("Foundation Models unavailable: \(SystemLanguageModel.default.availability)"); exit(2)
}

var report = "# AI Coach grounding eval (\(Date().formatted(date: .abbreviated, time: .shortened)))\n\n"
report += "Runs per condition: \(runs). Host: \(ProcessInfo.processInfo.operatingSystemVersionString).\n\n"
var summary: [String: (asks: Int, uses: Int, tools: Int, turns: Int, english: Int, wrong: Int)] = [:]
var transcripts = ""
for (label, grounded) in [("A 1.0.8 (66)", false), ("B 1.0.8 (67)", true)] {
    var tally = (asks: 0, uses: 0, tools: 0, turns: 0, english: 0, wrong: 0)
    for run in 1...runs {
        let turns = await runConversation(grounded: grounded)
        transcripts += "\n## \(label), run \(run)\n"
        for turn in turns {
            tally.turns += 1
            if turn.asks { tally.asks += 1 }
            if turn.usesData { tally.uses += 1 }
            if turn.english { tally.english += 1 }
            if turn.miscalculated { tally.wrong += 1 }
            tally.tools += turn.toolCalls
            transcripts += "\n**User:** \(turn.prompt)  \n**Coach** (tool calls \(turn.toolCalls), asks=\(turn.asks), usesData=\(turn.usesData), english=\(turn.english), wrongAverage=\(turn.miscalculated)):\n\n> \(turn.response.replacingOccurrences(of: "\n", with: "\n> "))\n"
        }
        print("\(label) run \(run) done")
    }
    summary[label] = tally
}
report += "| Condition | Turns | Asked the user / claimed no access | Quoted the user's data | English or scaffolding leaked | Wrong average | Tool calls |\n| --- | --- | --- | --- | --- | --- | --- |\n"
for label in ["A 1.0.8 (66)", "B 1.0.8 (67)"] {
    let t = summary[label]!
    report += "| \(label) | \(t.turns) | \(t.asks) | \(t.uses) | \(t.english) | \(t.wrong) | \(t.tools) |\n"
}
report += transcripts
try report.write(toFile: reportPath, atomically: true, encoding: .utf8)
print(report.prefix(700))
