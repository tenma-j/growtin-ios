import Foundation
import GrowtinCore
import SwiftData
import UIKit

extension AppModel {
    /// Modèle en mémoire pour les aperçus SwiftUI. Données d'exemple clairement fictives, jamais utilisées en production.
    static func preview(withProfile: Bool = false) -> AppModel {
        let container = try! GrowtinSchema.makeContainer(inMemory: true)
        let model = AppModel(container: container, notifications: PreviewNotificationService(), photoStore: .temporary())
        model.load()
        if withProfile {
            #if DEBUG
            model.seedDemo(days: 28)
            #else
            model.completeOnboarding(with: DemoData.profile(start: .now))
            #endif
        }
        return model
    }

    #if DEBUG
    /// Remplit le modèle avec un historique fictif de `days` jours (pour les aperçus et les captures).
    func seedDemo(days: Int, calendar: Calendar = .current) {
        let today = DayKey(.now, calendar: calendar)
        let start = today.adding(days: -(days - 1), calendar: calendar)
        let profile = DemoData.profile(start: start.date(calendar: calendar))
        let routine = RoutineEngine().initialRoutine(for: profile, startingOn: start)

        // Générateur déterministe : les captures sont identiques d'une exécution à l'autre.
        var seed: UInt64 = 42
        func random() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 33) / Double(1 << 31)
        }

        let sheddingOptions: [SheddingPerception] = [.usual, .usual, .less, .more, .notObserved]
        var completions: [HabitCompletion] = []
        var checkIns: [DailyCheckIn] = []
        for (offset, day) in DayKey.range(from: start, through: today.adding(days: -1, calendar: calendar), calendar: calendar).enumerated() {
            let progress = Double(offset) / Double(max(days - 1, 1))
            for item in routine where random() < 0.45 + 0.4 * progress {
                completions.append(HabitCompletion(itemID: item.id, day: day))
            }
            if random() < 0.8 {
                checkIns.append(DailyCheckIn(
                    day: day,
                    sleepHours: ((6 + 1.1 * progress + (random() - 0.5)) * 2).rounded() / 2,
                    stress: max(1, min(5, Int((4 - 1.5 * progress + random()).rounded()))),
                    shedding: sheddingOptions[Int(random() * 5) % 5]))
            }
        }
        // Aujourd'hui : deux habitudes déjà cochées.
        for item in routine.prefix(2) { completions.append(HabitCompletion(itemID: item.id, day: today)) }

        importDemoData(profile: profile, routine: routine, completions: completions, checkIns: checkIns)

        // Deux séries de photos synthétiques (clairement marquées « démonstration »).
        for (sessionIndex, day) in [start, today].enumerated() {
            for zone in PhotoZone.suggested(for: profile.zones) {
                let image = DemoData.syntheticPhoto(zone: zone, session: sessionIndex, day: day)
                guard let normalized = PhotoAnalysis.normalizedJPEG(from: image) else { continue }
                addPhoto(jpegData: normalized.data, zone: zone, camera: zone.preferredCamera,
                         quality: PhotoAnalysis.quality(of: normalized.image),
                         conditions: CaptureConditions(lighting: .window),
                         framing: FramingInfo(faceCenterX: 0.5, faceCenterY: 0.45, faceWidth: 0.45,
                                              devicePitch: 80, deviceRoll: Double(sessionIndex) * 3),
                         takenAt: day.date(calendar: calendar))
            }
        }
    }
    #endif
}

enum DemoData {
    static func profile(start: Date) -> UserProfile {
        var profile = UserProfile(firstName: "Alex", sex: .male, age: 28)
        profile.hairLossDuration = .sixMonthsTo2Years
        profile.triggers = [.stress, .genetics]
        profile.familyHistory = .fatherSide
        profile.stage = SelfAssessedStage(scale: .norwood, stage: 2)
        profile.zones = [.leftTemple, .rightTemple, .frontalHairline]
        profile.goals = [.buildHabits, .trackEvolution, .reduceStress]
        profile.sleepHours = 6
        profile.stress = .high
        profile.activity = .light
        profile.weightKg = 75
        profile.heightCm = 180
        profile.consents.wellnessDisclaimerAcceptedAt = start
        profile.programStartDate = start
        return profile
    }
}

extension DemoData {
    /// Image de démonstration dessinée par l'application : ce n'est pas une vraie photo.
    static func syntheticPhoto(zone: PhotoZone, session: Int, day: DayKey) -> UIImage {
        let size = CGSize(width: 900, height: 1200)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let top = UIColor(red: 0.80, green: 0.78, blue: 0.74, alpha: 1)
            let bottom = UIColor(red: 0.62, green: 0.60, blue: 0.57, alpha: 1)
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
            // Visage et cheveux stylisés.
            let skin = UIColor(red: 0.87, green: 0.72, blue: 0.62, alpha: 1)
            skin.setFill()
            UIBezierPath(ovalIn: CGRect(x: 230, y: 300, width: 440, height: 600)).fill()
            UIColor(white: 0.12, alpha: 1).setFill()
            let hair = UIBezierPath(ovalIn: CGRect(x: 210, y: 170, width: 480, height: 380))
            hair.fill()
            skin.setFill()
            let recession: CGFloat = 50 + CGFloat(session) * 6
            UIBezierPath(ovalIn: CGRect(x: 250, y: 470 - recession, width: 120, height: 120)).fill()
            UIBezierPath(ovalIn: CGRect(x: 530, y: 470 - recession, width: 120, height: 120)).fill()
            // Texture fine pour une netteté réaliste.
            UIColor(white: 0.25, alpha: 1).setStroke()
            for index in 0..<160 {
                let x = 230 + CGFloat((index * 37) % 440)
                let path = UIBezierPath()
                path.move(to: CGPoint(x: x, y: 200 + CGFloat((index * 53) % 120)))
                path.addLine(to: CGPoint(x: x + 6, y: 330 + CGFloat((index * 29) % 60)))
                path.lineWidth = 2
                path.stroke()
            }
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 40, weight: .semibold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph
            ]
            let label = "Photo de démonstration\n\(zone.label) · \(day)" as NSString
            label.draw(in: CGRect(x: 0, y: 1020, width: size.width, height: 120), withAttributes: attributes)
        }
    }
}

