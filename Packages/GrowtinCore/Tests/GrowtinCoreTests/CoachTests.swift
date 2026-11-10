import Foundation
import Testing
@testable import GrowtinCore

@Suite("Coach")
struct CoachTests {
    @Test("Découpage des citations")
    func segments() {
        let segments = CoachText.segments("Dors 7 h [S:watson-2015-sleep]. Bouge [S:who-2020-activity] !")
        #expect(segments == [.text("Dors 7 h "), .citation("watson-2015-sleep"), .text(". Bouge "), .citation("who-2020-activity"), .text(" !")])
        #expect(CoachText.segments("Sans citation") == [.text("Sans citation")])
        #expect(CoachText.segments("Crochet [S:Invalide] ici") == [.text("Crochet [S:Invalide]"), .text(" ici")])
        #expect(CoachText.plain("Dors 7 h [S:watson-2015-sleep].") == "Dors 7 h.")
    }

    @Test("Le contexte ne contient ni prénom ni âge exact")
    func contextIsMinimal() {
        var profile = UserProfile(firstName: "Jordan", sex: .male, age: 27)
        profile.sleepHours = 6
        profile.health.treatments = [.topicalMinoxidil]
        let day = DayKey(year: 2026, month: 11, day: 10)
        let context = CoachContextBuilder.build(
            profile: profile, routine: RoutineEngine().initialRoutine(for: profile, startingOn: day),
            consistency7Days: 0.74, checkIns: [DailyCheckIn(day: day, sleepHours: 6.5, stress: 4, note: "Journée chargée")],
            photoCount: 3, today: day)
        #expect(!context.contains("Jordan"))
        #expect(!context.contains("27"))
        #expect(context.contains("20-29 ans"))
        #expect(context.contains("minoxidil local"))
        #expect(context.contains("74 %"))
        #expect(context.contains("Journée chargée"))
    }

    @Test("Les anciens profils sans consentement Coach se décodent")
    func legacyProfileDecoding() throws {
        var data = try JSONEncoder().encode(UserProfile())
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var consents = json["consents"] as! [String: Any]
        consents.removeValue(forKey: "coachConsentAt")
        json["consents"] = consents
        data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(UserProfile.self, from: data)
        #expect(decoded.consents.coachConsentAt == nil)
    }

    @Test("Quota restant")
    func quota() {
        #expect(CoachQuota(used: 3, limit: 5, premium: false).remaining == 2)
        #expect(CoachQuota(used: 7, limit: 5, premium: false).remaining == 0)
    }
}
