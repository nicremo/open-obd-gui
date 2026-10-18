import Foundation
import Testing
import OBDCore
@testable import FordKnowledge

@Suite struct KnowledgeBaseTests {
    let knowledge = KnowledgeBase.bundled

    @Test func bundledKnowledgeIsValid() throws {
        try knowledge.validate()
        #expect(knowledge.modules.count >= 20)
        #expect(knowledge.dids.count >= 40)
        #expect(knowledge.dtcTitles.count >= 100)
        #expect(knowledge.dtcExplanations.count >= 15)
    }

    @Test func modulesFollowTheFordAddressConvention() throws {
        let pcm = try #require(knowledge.module(request: 0x7E0))
        #expect(pcm.acronym == "PCM")
        #expect(pcm.responseID == 0x7E8)
        #expect(pcm.confidence == .community)
        #expect(knowledge.module(request: 0x726)?.acronym == "BCM")
        #expect(knowledge.module(request: 0x7A0) == nil)
        #expect(knowledge.catalogAddresses == knowledge.catalogAddresses.sorted())
        #expect(knowledge.catalogAddresses.first == 0x706)
    }

    @Test func standardDIDsAreNormative() throws {
        let vin = try #require(knowledge.did(0xF190))
        #expect(vin.format == .vin)
        #expect(vin.confidence == .standard)
        #expect(knowledge.did(0xF111)?.confidence == .community)
        #expect(knowledge.did(0xF17D)?.confidence == .unknown)
        #expect(knowledge.did(0x1234) == nil)
    }

    @Test func troubleCodeTextsAreFound() throws {
        let title = try #require(knowledge.title(for: DTCCode("P0401")!))
        #expect(title.titleDE == "Abgasrückführung \"A\": Durchfluss zu gering")
        #expect(title.confidence == .standard)
        #expect(knowledge.title(for: DTCCode("P1000")!)?.confidence == .community)
        #expect(knowledge.explanation(for: DTCCode("P2463")!)?.causes.isEmpty == false)
        #expect(knowledge.title(for: DTCCode("B1A00")!) == nil)
    }

    @Test func partNumbersVINAndVehicles() {
        #expect(knowledge.partNumberBase("12A650")?.acronym == "PCM")
        #expect(knowledge.wmi(for: "WF0DXXGBBDSM12345")?.wmi == "WF0")
        #expect(knowledge.wmi(for: "XXX") == nil)
        #expect(knowledge.vehicle(id: "mondeo-mk4")?.expectedBuses == [.hsCAN, .msCAN])
    }

    @Test func validationRejectsDuplicatesAndBadData() {
        var broken = knowledge
        broken.modules.append(broken.modules[0])
        #expect(throws: KnowledgeError.self) { try broken.validate() }

        broken = knowledge
        broken.dtcTitles.append(DTCTitle(code: "Q123", titleDE: "x", source: "test", confidence: .community))
        #expect(throws: KnowledgeError.self) { try broken.validate() }

        broken = knowledge
        broken.dids.append(DIDDefinition(did: "XYZ1", nameDE: "x", nameEN: "x", format: .text, confidence: .unknown, source: "test"))
        #expect(throws: KnowledgeError.self) { try broken.validate() }

        broken = knowledge
        broken.dtcExplanations.append(DTCExplanation(code: "P0999", what: "x", urgency: "x", causes: [], source: "test", confidence: .community))
        #expect(throws: KnowledgeError.self) { try broken.validate() }

        broken = knowledge
        broken.vehicles[0].hints.append("Text mit Gedankenstrich \u{2013} verboten")
        #expect(throws: KnowledgeError.self) { try broken.validate() }
    }
}
