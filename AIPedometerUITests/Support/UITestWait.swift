import XCTest

@MainActor
enum UITestWait {
    static func firstExisting(
        _ candidates: [XCUIElement],
        timeout: TimeInterval
    ) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for el in candidates where el.exists {
                return el
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return candidates.first(where: { $0.exists })
    }

    static func assertAnyExists(
        _ candidates: [XCUIElement],
        timeout: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if let _ = firstExisting(candidates, timeout: timeout) {
            return
        }
        XCTFail("Nenhum candidato apareceu no tempo limite: \(candidates)", file: file, line: line)
    }

    static func tapFirstExisting(
        _ candidates: [XCUIElement],
        timeout: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let el = firstExisting(candidates, timeout: timeout) else {
            XCTFail("Elemento nao encontrado para tap: \(candidates)", file: file, line: line)
            return
        }
        el.tap()
    }
}
