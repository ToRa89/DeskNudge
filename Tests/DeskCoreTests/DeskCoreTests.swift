import XCTest
@testable import DeskCore

final class LinakCodecTests: XCTestCase {
    func testDecodesHeightAndSpeedLittleEndian() {
        // position 0x0C1C = 3100 (310.0 mm), speed 0xFF9C = -100
        let data = Data([0x1C, 0x0C, 0x9C, 0xFF])
        XCTAssertEqual(LinakCodec.decodeHeightSpeed(data), HeightSpeed(position: 3100, speed: -100))
    }

    func testRejectsShortPayload() {
        XCTAssertNil(LinakCodec.decodeHeightSpeed(Data([0x01, 0x02, 0x03])))
    }

    func testEncodesTargetLittleEndian() {
        XCTAssertEqual(LinakCodec.encodeTarget(3100), Data([0x1C, 0x0C]))
    }

    func testConvertsPositionToCentimetres() {
        XCTAssertEqual(LinakCodec.centimetres(position: 4930, baseHeightCm: 62.0), 111.3, accuracy: 0.001)
    }
}

final class MoveTrackerTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    private func tracker(target: UInt16 = 4000) -> MoveTracker {
        MoveTracker(target: target, startedAt: start)
    }

    func testKeepsGoingWhileMoving() {
        let outcome = tracker().evaluate(now: start + 2, sample: HeightSpeed(position: 2000, speed: 300))
        XCTAssertEqual(outcome, .keepGoing)
    }

    func testReachedWhenStoppedNearTarget() {
        let outcome = tracker().evaluate(now: start + 5, sample: HeightSpeed(position: 3995, speed: 0))
        XCTAssertEqual(outcome, .reached)
    }

    func testReachedImmediatelyWhenAlreadyAtTarget() {
        let outcome = tracker().evaluate(now: start, sample: HeightSpeed(position: 4000, speed: 0))
        XCTAssertEqual(outcome, .reached)
    }

    func testWaitsForSettleDelayBeforeJudgingStandstill() {
        let outcome = tracker().evaluate(now: start + 0.5, sample: HeightSpeed(position: 2000, speed: 0))
        XCTAssertEqual(outcome, .keepGoing)
    }

    func testStoppedShortWhenStandstillFarFromTarget() {
        let outcome = tracker().evaluate(now: start + 3, sample: HeightSpeed(position: 2500, speed: 0))
        XCTAssertEqual(outcome, .stoppedShort(2500))
    }

    func testTimesOut() {
        let outcome = tracker().evaluate(now: start + 120, sample: HeightSpeed(position: 2500, speed: 200))
        XCTAssertEqual(outcome, .timedOut)
    }

    func testKeepsGoingWithoutSampleUntilTimeout() {
        XCTAssertEqual(tracker().evaluate(now: start + 1, sample: nil), .keepGoing)
    }
}

final class ReminderLogicTests: XCTestCase {
    private let favourites = Favourites(sit: 1200, stand: 4900)

    func testPostureBelowMidpointIsSitting() {
        XCTAssertEqual(ReminderLogic.posture(position: 1500, favourites: favourites), .sitting)
    }

    func testPostureAboveMidpointIsStanding() {
        XCTAssertEqual(ReminderLogic.posture(position: 4000, favourites: favourites), .standing)
    }

    func testDueAfterSitInterval() {
        let since = Date(timeIntervalSince1970: 0)
        let settings = DeskSettings(sitMinutes: 45, standMinutes: 15)
        XCTAssertEqual(ReminderLogic.dueDate(posture: .sitting, since: since, settings: settings), since + 45 * 60)
        XCTAssertEqual(ReminderLogic.dueDate(posture: .standing, since: since, settings: settings), since + 15 * 60)
    }

    func testSuggestionTargetsOppositeFavourite() {
        XCTAssertEqual(ReminderLogic.target(after: .sitting, favourites: favourites), 4900)
        XCTAssertEqual(ReminderLogic.target(after: .standing, favourites: favourites), 1200)
    }
}

final class DeskSettingsTests: XCTestCase {
    func testRoundTripsThroughJSON() throws {
        let original = DeskSettings(
            deskID: UUID(), deskName: "Desk 1234", sitPosition: 1200, standPosition: 4900,
            baseHeightCm: 64.5, sitMinutes: 50, standMinutes: 10, remindersEnabled: false
        )
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(DeskSettings.self, from: data), original)
    }

    func testFavouritesOnlyWhenBothSet() {
        XCTAssertNil(DeskSettings(sitPosition: 1200).favourites)
        XCTAssertEqual(DeskSettings(sitPosition: 1200, standPosition: 4900).favourites, Favourites(sit: 1200, stand: 4900))
    }
}

final class HeightInputTests: XCTestCase {
    func testConvertsCentimetresToPosition() {
        XCTAssertEqual(LinakCodec.position(centimetres: 111.3, baseHeightCm: 62.0), 4930)
    }

    func testRejectsHeightBelowBase() {
        XCTAssertNil(LinakCodec.position(centimetres: 60.0, baseHeightCm: 62.0))
    }

    func testRejectsHeightAboveStroke() {
        XCTAssertNil(LinakCodec.position(centimetres: 62.0 + 80.0, baseHeightCm: 62.0))
    }

    func testAcceptsBaseItself() {
        XCTAssertEqual(LinakCodec.position(centimetres: 62.0, baseHeightCm: 62.0), 0)
    }
}

final class CustomFavouriteTests: XCTestCase {
    func testDecodesSettingsSavedByVersion01() throws {
        let legacy = #"{"baseHeightCm":62,"sitMinutes":5,"standMinutes":5,"remindersEnabled":true,"sitPosition":1200,"standPosition":4900}"#
        let decoded = try JSONDecoder().decode(DeskSettings.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.favourites, Favourites(sit: 1200, stand: 4900))
        XCTAssertNil(decoded.customPosition)
        XCTAssertEqual(decoded.customDisplayName, "Favorit 3")
    }

    func testCustomNameFallsBackWhenBlank() {
        XCTAssertEqual(DeskSettings(customName: "  ").customDisplayName, "Favorit 3")
        XCTAssertEqual(DeskSettings(customName: "Meeting").customDisplayName, "Meeting")
    }
}

final class JogCommandTests: XCTestCase {
    func testJogCommands() {
        XCTAssertEqual(LinakCommand.up, Data([0x47, 0x00]))
        XCTAssertEqual(LinakCommand.down, Data([0x46, 0x00]))
    }
}
