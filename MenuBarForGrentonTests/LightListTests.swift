import Foundation
import GrentonKit
import GrentonSimulation
import Testing
@testable import MenuBarForGrenton

// The fixture is synthetic: three pages — A with a light above the first
// header, a dimmer, a double switch, an RGB light, a relay with a valve icon,
// a shutter with stop and slats, and a section with sensors only; B with
// nothing to show; C with one relay shown by two widgets and a shutter
// without stop or slats.

private final class BundleToken {}

private func fixtureData() throws -> Data {
    let url = try #require(Bundle(for: BundleToken.self).url(forResource: "test-interface", withExtension: "json"))
    return try Data(contentsOf: url)
}

private func interface(withoutHeaders: Bool = false) throws -> MobileInterfaceDTO {
    var data = try fixtureData()
    if withoutHeaders {
        var root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let pages = try #require(root["pages"] as? [[String: Any]])
        root["pages"] = pages.map { page in
            var page = page
            page["widgets"] = (page["widgets"] as? [[String: Any]] ?? []).filter { $0["type"] as? String != "HEADER" }
            return page
        }
        data = try JSONSerialization.data(withJSONObject: root)
    }
    return try JSONDecoder().decode(MobileInterfaceDTO.self, from: data)
}

@MainActor
private func build(_ interface: MobileInterfaceDTO) -> (SimulatedGrentonSystem, [HomePage]) {
    let simulation = SimulatedGrentonSystem(interface: interface)
    let pages = HomeListBuilder.pages(devices: simulation.devices, physicalObjects: simulation.physicalObjects)
    return (simulation, pages)
}

/// The relay entity of `light`, or a recorded issue.
@MainActor
private func toggle(_ light: LightItem) -> ToggleEntity? {
    guard case .toggle(let toggle) = light.entity else { Issue.record("not a toggle"); return nil }
    return toggle
}

@MainActor
struct LightListTests {
    @Test func pagesFollowTheInterfaceAndSkipPagesWithoutLights() throws {
        let (_, pages) = build(try interface())
        #expect(pages.map(\.name) == ["Strona A", "Strona C"])
        #expect(pages.map(\.id) == [0, 2])
    }

    @Test func headersSplitAPageIntoSectionsInWidgetOrder() throws {
        let (_, pages) = build(try interface())
        let page = pages[0]
        #expect(page.sections.map(\.title) == [nil, "Sekcja A-1", "Sekcja A-3"])
        #expect(page.sections.map { $0.lights.map(\.name) } == [
            ["Lampa A1"],
            ["Ściemniacz A2"],
            ["Lewa A3", "Prawa A3", "Taśma A4"],
        ])
        // The shutter sits after the lights of its section, as in the interface.
        #expect(page.sections[2].rows.count == 4)
        guard case .cover(let last) = page.sections[2].rows[3] else { Issue.record("not a shutter"); return }
        #expect(last.name == "Roleta A6")
    }

    @Test func shuttersAreRowsAfterTheLightsOfTheirWidgetOrder() throws {
        let (_, pages) = build(try interface())
        #expect(pages.map { $0.covers.map(\.name) } == [["Roleta A6"], ["Roleta C3"]])
        let withSlats = try #require(pages[0].covers.first)
        let plain = try #require(pages[1].covers.first)
        #expect(withSlats.supportsStop && withSlats.supportsTilt)
        #expect(!plain.supportsStop && !plain.supportsTilt)
    }

    @Test func sectionIdsAreUniqueAcrossPages() throws {
        let (_, pages) = build(try interface())
        let ids = pages.flatMap { $0.sections.map(\.id) }
        #expect(Set(ids).count == ids.count)
    }

    @Test func everyLightKindIsALightAndNothingElseIs() throws {
        let (_, pages) = build(try interface())
        let kinds = pages[0].lights.map { light -> String in
            switch light.entity {
            case .toggle: "toggle"
            case .dimmableLight: "dimmable"
            case .hsbLight: "hsb"
            default: "other"
            }
        }
        #expect(kinds == ["toggle", "dimmable", "toggle", "toggle", "hsb"])
    }

    @Test func aRelayWithoutALampIconIsNotALight() throws {
        let (simulation, _) = build(try interface())
        let valve = try #require(simulation.devices.first { $0.id == "demow0025" }?.entities.first)
        #expect(valve.switchable != nil)
        #expect(LightItem(valve) == nil)
    }

    @Test func theRowSymbolFollowsTheIcon() throws {
        let (_, pages) = build(try interface())
        #expect(pages[0].lights[0].symbol(on: false) == "lightbulb")
        #expect(pages[0].lights[4].symbol(on: true) == "light.strip.2.fill")
        #expect(pages[1].lights[2].symbol(on: false) == "light.recessed")
    }

    @Test func withHeadersAWidgetShowingTheSameObjectTwiceStaysTwice() throws {
        let (_, pages) = build(try interface())
        #expect(pages[1].lights.map(\.name) == ["Lampa C1", "Lampa C1 duplikat", "Lampa C2"])
    }

    @Test func withoutHeadersEachPageIsOneSectionAndAnObjectAppearsOnce() throws {
        let (_, pages) = build(try interface(withoutHeaders: true))
        #expect(pages.map(\.name) == ["Strona A", "Strona C"])
        #expect(pages.allSatisfy { $0.sections.count == 1 && $0.sections[0].title == nil })
        #expect(pages[0].lights.map(\.name) == ["Lampa A1", "Ściemniacz A2", "Lewa A3", "Prawa A3", "Taśma A4"])
        #expect(pages[1].lights.map(\.name) == ["Lampa C1", "Lampa C2"])
    }

    @Test func stateIsUnknownUntilTheCluReportsIt() throws {
        let (simulation, pages) = build(try interface())
        let light = pages[1].lights[2]
        guard let toggle = toggle(light) else { return }
        #expect(light.isOn == nil)
        simulation.set(toggle.descriptor.state, to: .int(1))
        #expect(light.isOn == true)
    }

    @Test func aReportReachesTheObservedRow() async throws {
        let (simulation, pages) = build(try interface())
        let light = pages[0].lights[1]
        guard case .dimmableLight(let dimmer) = light.entity else { Issue.record("not a dimmer"); return }
        simulation.set(dimmer.descriptor.state, to: .double(40))
        for _ in 0..<100 where light.observed.changeCount == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(light.observed.changeCount > 0)
        #expect(light.isOn == true)
    }

    @Test func switchingALightSendsItsAction() async throws {
        let (simulation, pages) = build(try interface())
        let light = pages[0].lights[0]
        guard let toggle = toggle(light) else { return }
        light.confirmationTimeout = .milliseconds(20)
        try await light.setOn(true)
        try await light.setOn(false)
        #expect(simulation.executedActions == [toggle.descriptor.onAction, toggle.descriptor.offAction])
    }

    @Test func theSwitchShowsTheRequestedStateUntilTheCluConfirms() async throws {
        let (simulation, pages) = build(try interface())
        let light = pages[0].lights[0]
        guard let toggle = toggle(light) else { return }
        simulation.set(toggle.descriptor.state, to: .int(0))

        let command = Task { try await light.setOn(true) }
        await Task.yield()
        #expect(light.displayedOn == true)
        #expect(light.isOn == false)

        simulation.set(toggle.descriptor.state, to: .int(1))
        #expect(try await command.value == true)
        #expect(light.pendingOn == nil)
        #expect(light.displayedOn == true)
    }

    @Test func withoutConfirmationTheSwitchFallsBackToTheCluState() async throws {
        let (simulation, pages) = build(try interface())
        let light = pages[0].lights[0]
        guard let toggle = toggle(light) else { return }
        simulation.set(toggle.descriptor.state, to: .int(0))
        light.confirmationTimeout = .milliseconds(30)
        #expect(try await light.setOn(true) == false)
        #expect(light.pendingOn == nil)
        #expect(light.displayedOn == false)
    }

    @Test func aFailedCommandThrowsAndFallsBackToTheCluState() async throws {
        let (simulation, pages) = build(try interface())
        let light = pages[0].lights[0]
        guard let toggle = toggle(light) else { return }
        simulation.set(toggle.descriptor.state, to: .int(0))
        simulation.failCommands(with: SessionError.timeout)
        await #expect(throws: SessionError.timeout) { try await light.setOn(true) }
        #expect(light.pendingOn == nil)
        #expect(light.displayedOn == false)
    }

    @Test func aNewerCommandKeepsItsPendingStateWhenTheOlderOneEnds() async throws {
        let (simulation, pages) = build(try interface())
        let light = pages[0].lights[0]
        guard let toggle = toggle(light) else { return }
        simulation.set(toggle.descriptor.state, to: .int(0))
        light.confirmationTimeout = .milliseconds(30)
        let first = Task { try await light.setOn(true) }
        await Task.yield()
        light.confirmationTimeout = .seconds(5)
        let second = Task { try await light.setOn(false) }
        await Task.yield()
        _ = try await first.value
        // The first gave up; the second still shows its request (off, the CLU's state too).
        #expect(light.displayedOn == false)
        #expect(try await second.value == true)
    }
}

@MainActor
struct CoverItemTests {
    private func shutter(withSlats: Bool = true) throws -> (SimulatedGrentonSystem, CoverItem, CoverEntity) {
        let (simulation, pages) = build(try interface())
        let item = try #require(pages[withSlats ? 0 : 1].covers.first)
        guard case .cover(let entity) = item.entity else { throw CancellationError() }
        item.confirmationTimeout = .milliseconds(30)
        return (simulation, item, entity)
    }

    @Test func theStateTextFollowsPositionAndMotion() throws {
        let (simulation, item, entity) = try shutter()
        #expect(item.stateText == "–")
        simulation.set(entity.descriptor.position, to: .int(0))
        #expect(item.stateText == "zamknięta")
        #expect(item.looksClosed)
        simulation.set(entity.descriptor.position, to: .int(40))
        #expect(item.stateText == "40 %")
        simulation.set(entity.descriptor.motionState, to: .int(1))
        #expect(item.stateText == "otwiera się…")
        simulation.set(entity.descriptor.motionState, to: .int(0))
        simulation.set(entity.descriptor.position, to: .int(100))
        #expect(item.stateText == "otwarta")
    }

    @Test func openCloseAndTiltSendTheirActionsWithValues() async throws {
        let (simulation, item, entity) = try shutter()
        simulation.set(entity.descriptor.position, to: .int(50))
        try await item.perform(.open)
        try await item.perform(.close)
        try await item.perform(.tilt(100))
        try await item.perform(.stop)
        let sent = simulation.executedActions
        #expect(sent.count == 4)
        #expect(sent[0].value == "100" && sent[1].value == "0")
        #expect(sent[2] == entity.descriptor.tilt?.setAction.withValue("0"))
        #expect(sent[3] == entity.descriptor.stopAction)
    }

    @Test func aShutterWithoutStopOrSlatsIgnoresThoseCommands() async throws {
        let (simulation, item, _) = try shutter(withSlats: false)
        #expect(try await item.perform(.stop) == true)
        #expect(try await item.perform(.tilt(50)) == true)
        #expect(simulation.executedActions.isEmpty)
    }

    @Test func theRowShowsTheCommandUntilTheCluReportsAnything() async throws {
        let (simulation, item, entity) = try shutter()
        simulation.set(entity.descriptor.position, to: .int(0))
        item.confirmationTimeout = .seconds(5)

        let command = Task { try await item.perform(.open) }
        await Task.yield()
        #expect(item.pending == .open)
        #expect(item.stateText == "otwieram…")
        #expect(!item.looksClosed)

        simulation.set(entity.descriptor.motionState, to: .int(1))
        #expect(try await command.value == true)
        #expect(item.pending == nil)
        #expect(item.stateText == "otwiera się…")
    }

    @Test func withoutAReportTheRowFallsBackToTheCluState() async throws {
        let (simulation, item, entity) = try shutter()
        simulation.set(entity.descriptor.position, to: .int(0))
        #expect(try await item.perform(.open) == false)
        #expect(item.pending == nil)
        #expect(item.stateText == "zamknięta")
    }

    @Test func aCommandTheShutterHasNothingToDoForIsConfirmedAtOnce() async throws {
        let (simulation, item, entity) = try shutter()
        simulation.set(entity.descriptor.position, to: .int(100))
        simulation.set(entity.descriptor.motionState, to: .int(0))
        #expect(try await item.perform(.open) == true)
        #expect(simulation.executedActions.count == 1)
    }

    @Test func aFailedCommandThrowsAndClearsThePendingState() async throws {
        let (simulation, item, _) = try shutter()
        simulation.failCommands(with: SessionError.timeout)
        await #expect(throws: SessionError.timeout) { try await item.perform(.close) }
        #expect(item.pending == nil)
    }

    @Test func theRequestedTiltShowsUntilConfirmed() async throws {
        let (simulation, item, entity) = try shutter()
        let slats = try #require(entity.descriptor.tilt)
        simulation.set(slats.position, to: .int(90))
        #expect(item.tilt == 0)
        item.confirmationTimeout = .seconds(5)
        let command = Task { try await item.perform(.tilt(60)) }
        await Task.yield()
        #expect(item.displayedTilt == 60)
        simulation.set(slats.position, to: .int(36))
        #expect(try await command.value == true)
        #expect(item.displayedTilt == 60)
    }
}

struct ConnectionStatusTests {
    private let clus = [
        Clu(id: "CLU_1", serialNumber: "1", name: "Dół", ip: "10.0.0.1", port: 1234, connectionType: .localOnly),
        Clu(id: "CLU_2", serialNumber: "2", name: "Góra", ip: "10.0.0.2", port: 1234, connectionType: .localOnly),
    ]

    private func status(_ states: [String: (SessionState, Duration?)]) -> ConnectionStatus {
        ConnectionStatus.from(states.mapValues { SessionDiagnostics(state: $0.0, sinceLastReply: $0.1) }, clus: clus)
    }

    @Test func allReadyIsConnected() {
        #expect(status(["CLU_1": (.ready, .seconds(1)), "CLU_2": (.ready, .seconds(1))]) == .connected(cluCount: 2))
    }

    @Test func oneDegradedIsPartialWithItsName() {
        #expect(status(["CLU_1": (.ready, .seconds(1)), "CLU_2": (.degraded, .seconds(30))])
            == .partial(down: ["Góra"], cluCount: 2))
    }

    @Test func allDegradedWithoutAnyReplyPointsToLocalNetwork() {
        #expect(status(["CLU_1": (.degraded, nil), "CLU_2": (.degraded, nil)]) == .offline(neverAnswered: true))
        #expect(status(["CLU_1": (.degraded, .seconds(40)), "CLU_2": (.degraded, nil)]) == .offline(neverAnswered: false))
    }

    @Test func startingIsConnectingAndIdleIsStopped() {
        #expect(status(["CLU_1": (.ready, .seconds(1)), "CLU_2": (.starting, nil)]) == .connecting)
        #expect(status(["CLU_1": (.idle, nil), "CLU_2": (.idle, nil)]) == .stopped)
        #expect(ConnectionStatus.from([:], clus: clus) == .stopped)
    }
}

@MainActor
struct SyntheticInterfaceTests {
    /// A typo in a hand-written widget skips it silently (NOTES.md D4); both synthetic interfaces must decode whole.
    @Test func demoAndTestInterfacesSkipNoWidget() throws {
        #expect(try interface().skippedWidgets.isEmpty)
        #expect(try DemoDriver.demoInterface().skippedWidgets.isEmpty)
    }
}
