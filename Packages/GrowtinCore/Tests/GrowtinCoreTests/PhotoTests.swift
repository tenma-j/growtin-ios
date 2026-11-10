import Foundation
import Testing
@testable import GrowtinCore

@Suite("Qualité des photos")
struct ImageQualityTests {
    func image(_ size: Int = 64, _ value: (Int, Int) -> UInt8) -> GrayImage {
        var pixels: [UInt8] = []
        for y in 0..<size { for x in 0..<size { pixels.append(value(x, y)) } }
        return GrayImage(width: size, height: size, pixels: pixels)!
    }

    @Test("Une image texturée est nette, une image uniforme est floue")
    func sharpness() {
        let sharp = ImageQualityAnalyzer.analyze(image { x, y in (x + y) % 2 == 0 ? 40 : 200 })
        let flat = ImageQualityAnalyzer.analyze(image { _, _ in 128 })
        #expect(sharp.sharpness > ImageQualityAnalyzer.Thresholds.slightlyBlurry)
        #expect(flat.sharpness == 0)
        #expect(ImageQualityAnalyzer.assess(flat).issues.contains { $0.kind == .blurry })
    }

    @Test("Luminosité et écrêtage")
    func exposure() {
        let dark = ImageQualityAnalyzer.analyze(image { x, y in (x + y) % 2 == 0 ? 0 : 60 })
        #expect(dark.brightness < ImageQualityAnalyzer.Thresholds.tooDark)
        #expect(dark.clippedShadows > 0.4)
        let assessment = ImageQualityAnalyzer.assess(dark)
        #expect(assessment.level == .poor)
        #expect(assessment.issues.contains { $0.kind == .tooDark })

        let good = ImageQualityAnalyzer.analyze(image { x, y in (x * 7 + y * 13) % 2 == 0 ? 90 : 170 })
        #expect(ImageQualityAnalyzer.assess(good).level == .good)
    }

    @Test("Dimensions invalides refusées")
    func invalidImage() {
        #expect(GrayImage(width: 2, height: 2, pixels: [0, 0, 0, 0]) == nil)
        #expect(GrayImage(width: 10, height: 10, pixels: [0]) == nil)
    }
}

@Suite("Comparabilité des photos")
struct ComparabilityTests {
    let good = ImageQuality(sharpness: 300, brightness: 0.5, clippedHighlights: 0, clippedShadows: 0)

    func photo(zone: PhotoZone = .frontalHairline, day: DayKey, camera: CameraPosition = .front,
               quality: ImageQuality? = nil, conditions: CaptureConditions = CaptureConditions(),
               framing: FramingInfo = FramingInfo()) -> PhotoEntry {
        PhotoEntry(zone: zone, day: day, takenAt: day.date(), fileName: "x.jpg", camera: camera,
                   quality: quality ?? good, conditions: conditions, framing: framing)
    }

    let d0 = DayKey(year: 2026, month: 1, day: 1)
    var d60: DayKey { d0.adding(days: 60) }

    @Test("Conditions identiques : comparable")
    func identical() {
        let report = ComparabilityAnalyzer.compare(photo(day: d0), photo(day: d60))
        #expect(report.level == .high)
        #expect(report.reasons.isEmpty)
        #expect(report.daysApart == 60)
    }

    @Test("Zones différentes : non comparable")
    func differentZones() {
        let report = ComparabilityAnalyzer.compare(photo(zone: .vertex, day: d0), photo(day: d60))
        #expect(report.level == .low)
    }

    @Test("Cheveux mouillés et lumière différente : peu fiable")
    func wetAndLighting() {
        let wet = CaptureConditions(dryHair: false, lighting: .bathroom)
        let report = ComparabilityAnalyzer.compare(photo(day: d0), photo(day: d60, conditions: wet))
        #expect(report.level == .low)
        #expect(report.reasons.contains { $0.contains("mouillés") })
        #expect(report.reasons.contains { $0.contains("lumière") })
    }

    @Test("Cadrage et luminosité différents pénalisés")
    func framingAndBrightness() {
        let a = photo(day: d0, framing: FramingInfo(faceCenterX: 0.5, faceCenterY: 0.6, faceWidth: 0.4))
        let darker = ImageQuality(sharpness: 300, brightness: 0.3, clippedHighlights: 0, clippedShadows: 0)
        let b = photo(day: d60, quality: darker, framing: FramingInfo(faceCenterX: 0.3, faceCenterY: 0.6, faceWidth: 0.6))
        let report = ComparabilityAnalyzer.compare(a, b)
        #expect(report.level == .low)
        #expect(report.reasons.count >= 3)
    }

    @Test("Intervalle court signalé, ordre indifférent")
    func shortInterval() {
        let later = d0.adding(days: 7)
        let report = ComparabilityAnalyzer.compare(photo(day: later), photo(day: d0))
        #expect(report.daysApart == 7)
        #expect(report.reasons.contains { $0.contains("4 semaines") })
    }

    @Test("Aucun rapport ne mesure les cheveux")
    func noHairMeasurement() {
        let report = ComparabilityAnalyzer.compare(photo(day: d0), photo(day: d60, conditions: CaptureConditions(dryHair: false)))
        for text in report.reasons + [ComparabilityReport.disclaimer] {
            let lower = text.lowercased()
            #expect(!lower.contains("repousse ") || lower.contains("ne mesure"))
            #expect(!lower.contains("%"))
        }
    }
}

@Suite("Zones et frise")
struct PhotoTimelineTests {
    @Test("Zones suggérées à partir de l'onboarding")
    func suggestedZones() {
        #expect(PhotoZone.suggested(for: []) == [.frontalHairline, .leftTemple, .rightTemple, .vertex])
        #expect(PhotoZone.suggested(for: [.diffuse]) == [.top, .centralPart])
        #expect(PhotoZone.suggested(for: [.vertex, .leftTemple]) == [.leftTemple, .vertex])
    }

    @Test("Dernière série et comparaison par défaut")
    func timeline() throws {
        let d0 = DayKey(year: 2026, month: 1, day: 1)
        let blurry = ImageQuality(sharpness: 5, brightness: 0.5, clippedHighlights: 0, clippedShadows: 0)
        let good = ImageQuality(sharpness: 300, brightness: 0.5, clippedHighlights: 0, clippedShadows: 0)
        let photos = [0, 28, 56, 84].map { offset in
            PhotoEntry(zone: .vertex, day: d0.adding(days: offset), takenAt: d0.adding(days: offset).date(),
                       fileName: "\(offset).jpg", camera: .back, quality: offset == 84 ? blurry : good,
                       conditions: CaptureConditions())
        }
        #expect(PhotoTimeline.lastSessionDay(photos) == d0.adding(days: 84))
        let pair = try #require(PhotoTimeline.defaultComparison(photos, zone: .vertex))
        #expect(pair.before.fileName == "0.jpg")
        #expect(pair.after.fileName == "56.jpg") // la photo floue est écartée
        #expect(PhotoTimeline.defaultComparison(photos, zone: .frontalHairline) == nil)
    }
}
