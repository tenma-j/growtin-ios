import Combine
import Charts
import GrowtinCore
import SwiftUI

enum ProgressPeriod: Int, CaseIterable, Identifiable {
    case week = 7, month = 30, quarter = 90, half = 180, year = 365

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .week: "7 j"
        case .month: "30 j"
        case .quarter: "3 mois"
        case .half: "6 mois"
        case .year: "12 mois"
        }
    }

    var bucket: Calendar.Component {
        switch self {
        case .week, .month: .day
        case .quarter, .half: .weekOfYear
        case .year: .month
        }
    }
}

/// Point agrégé du graphique de régularité.
struct RegularityPoint: Identifiable, Hashable {
    let date: Date
    let completed: Int
    let scheduled: Int
    var id: Date { date }
    var ratio: Double { scheduled == 0 ? 0 : Double(completed) / Double(scheduled) }
}

enum ProgressAggregator {
    static func points(from series: [DayProgress], bucket: Calendar.Component, calendar: Calendar = .current) -> [RegularityPoint] {
        let grouped = Dictionary(grouping: series.filter { $0.scheduled > 0 }) { progress -> Date in
            let date = progress.day.date(calendar: calendar)
            return calendar.dateInterval(of: bucket, for: date)?.start ?? date
        }
        return grouped.map { date, values in
            RegularityPoint(date: date,
                            completed: values.reduce(0) { $0 + $1.completed },
                            scheduled: values.reduce(0) { $0 + $1.scheduled })
        }
        .sorted { $0.date < $1.date }
    }
}

struct ProgressTabView: View {
    @Environment(AppModel.self) private var model
    @State private var period: ProgressPeriod = .month
    @State private var today = DayKey(.now)
    @State private var path: [PhotoRoute] = []
    @State private var showingPhotoSession = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: GT.Spacing.l) {
                    PhotoTrackingCard(today: today) { showingPhotoSession = true }

                    Picker("Période", selection: $period) {
                        ForEach(ProgressPeriod.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    RegularityChartCard(period: period, today: today)
                    WellbeingChartCard(period: period, today: today)
                    ForecastSection(today: today)
                    UpcomingCard(period: period, today: today)
                    RoadmapCard(today: today)
                    FootnoteText(text: Roadmap.disclaimer)
                }
                .padding(.horizontal, GT.Spacing.m)
                .padding(.bottom, GT.Spacing.xl)
            }
            .background(Color.gtBackground)
            .navigationTitle("Progrès")
            .navigationDestination(for: PhotoRoute.self) { route in
                switch route {
                case .zone(let zone):
                    ZoneTimelineView(zone: zone)
                case .photo(let id):
                    if let entry = model.photo(id: id) {
                        PhotoDetailView(entry: entry)
                    } else {
                        ContentUnavailableView("Photo supprimée", systemImage: "photo")
                    }
                case .compare(let before, let after):
                    if let first = model.photo(id: before), let second = model.photo(id: after) {
                        PhotoCompareView(first: first, second: second)
                    } else {
                        ContentUnavailableView("Photo supprimée", systemImage: "photo")
                    }
                }
            }
            .fullScreenCover(isPresented: $showingPhotoSession) {
                PhotoSessionView(startAtCapture: DemoLaunch.screen == "photoCapture")
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in today = DayKey(.now) }
            .task { openDemoScreenIfNeeded() }
        }
    }

    /// Navigation automatique pour les captures d'écran du mode démonstration.
    private func openDemoScreenIfNeeded() {
        switch DemoLaunch.screen {
        case "photoSession", "photoCapture":
            showingPhotoSession = true
        case "photoTimeline":
            if let zone = model.photoZones.first { path = [.zone(zone)] }
        case "photoCompare":
            if let zone = model.photoZones.first, let pair = PhotoTimeline.defaultComparison(model.photos, zone: zone) {
                path = [.zone(zone), .compare(before: pair.before.id, after: pair.after.id)]
            }
        default:
            break
        }
    }
}

private struct RegularityChartCard: View {
    @Environment(AppModel.self) private var model
    let period: ProgressPeriod
    let today: DayKey
    @State private var selectedDate: Date?

    var body: some View {
        let calculator = model.consistency
        let series = calculator.series(endingOn: today, days: period.rawValue)
        let points = ProgressAggregator.points(from: series, bucket: period.bucket)
        let overall = calculator.consistency(endingOn: today, days: period.rawValue)
        let selected = selectedDate.flatMap { date in
            points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
        }

        GTCard {
            SectionHeader(title: "Régularité",
                          subtitle: overall.map { "\($0.formatted(.percent.precision(.fractionLength(0)))) des habitudes prévues réalisées" })
            if points.isEmpty {
                ContentUnavailableView("Pas encore de données", systemImage: "chart.bar",
                                       description: Text("Coche tes habitudes pour voir ta régularité évoluer."))
                    .frame(height: 180)
            } else {
                Chart {
                    ForEach(points) { point in
                        BarMark(x: .value("Date", point.date, unit: period.bucket),
                                y: .value("Régularité", point.ratio))
                            .foregroundStyle(Color.gtRegularity.gradient)
                            .cornerRadius(4)
                            .opacity(selected == nil || selected == point ? 1 : 0.4)
                    }
                    if let selected {
                        RuleMark(x: .value("Sélection", selected.date, unit: period.bucket))
                            .foregroundStyle(HierarchicalShapeStyle.secondary.opacity(0.3))
                            .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                VStack(spacing: 2) {
                                    Text(selected.ratio.formatted(.percent.precision(.fractionLength(0))))
                                        .font(.headline)
                                    Text("\(selected.completed)/\(selected.scheduled)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(GT.Spacing.xs)
                                .glassEffect(.regular, in: .rect(cornerRadius: GT.Radius.small))
                            }
                    }
                }
                .chartYScale(domain: 0...1)
                .chartYAxis {
                    AxisMarks(values: [0, 0.5, 1]) { value in
                        AxisGridLine()
                        AxisValueLabel { Text((value.as(Double.self) ?? 0).formatted(.percent.precision(.fractionLength(0)))) }
                    }
                }
                .chartXSelection(value: $selectedDate)
                .frame(height: 200)
                .accessibilityLabel("Graphique de régularité")
            }
            Text(WellnessNotice.regularity)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Sommeil et stress issus des bilans du jour.
private struct WellbeingChartCard: View {
    @Environment(AppModel.self) private var model
    let period: ProgressPeriod
    let today: DayKey

    struct Point: Identifiable {
        let date: Date
        let value: Double
        let series: String
        var id: String { "\(series)-\(date.timeIntervalSince1970)" }
    }

    var body: some View {
        let start = today.adding(days: -(period.rawValue - 1))
        let checkIns = model.checkIns.values.filter { $0.day >= start && $0.day <= today }.sorted { $0.day < $1.day }
        let sleep = checkIns.compactMap { c in c.sleepHours.map { Point(date: c.day.date(), value: $0, series: "Sommeil (h)") } }
        let stress = checkIns.compactMap { c in c.stress.map { Point(date: c.day.date(), value: Double($0), series: "Stress (1-5)") } }
        let moreShedding = checkIns.filter { $0.shedding == .more }.count
        let observations = checkIns.filter { $0.shedding != nil && $0.shedding != .notObserved }.count

        GTCard {
            SectionHeader(title: "Sommeil, stress et observations", subtitle: "D'après tes bilans du jour")
            if sleep.count + stress.count < 2 {
                ContentUnavailableView("Pas encore assez de bilans", systemImage: "moon.zzz",
                                       description: Text("Quelques bilans du jour suffisent pour afficher tes tendances."))
                    .frame(height: 160)
            } else {
                Chart(sleep + stress) { point in
                    LineMark(x: .value("Date", point.date, unit: .day), y: .value("Valeur", point.value))
                        .foregroundStyle(by: .value("Mesure", point.series))
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Date", point.date, unit: .day), y: .value("Valeur", point.value))
                        .foregroundStyle(by: .value("Mesure", point.series))
                        .symbolSize(20)
                }
                .chartForegroundStyleScale(["Sommeil (h)": Color.indigo, "Stress (1-5)": Color.gtRegularity])
                .frame(height: 180)
            }
            if observations > 0 {
                Text("Chute perçue « plus que d'habitude » : \(moreShedding) jour\(moreShedding > 1 ? "s" : "") sur \(observations) observé\(observations > 1 ? "s" : "").")
                    .font(.subheadline)
            }
            Text("Ces courbes montrent des associations dans tes données, pas des causes. Une variation ponctuelle de la chute perçue est fréquente.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ForecastSection: View {
    @Environment(AppModel.self) private var model
    let today: DayKey

    var body: some View {
        let forecaster = HabitForecaster()
        let yesterday = today.adding(days: -1)
        // On n'utilise que les jours passés et complets, depuis le début du programme.
        let start = max(model.programStart, today.adding(days: -90))
        var regularity: [DayKey: Double] = [:]
        for progress in model.consistency.series(endingOn: yesterday, days: max(1, start.days(until: yesterday) + 1)) {
            if let ratio = progress.ratio { regularity[progress.day] = ratio }
        }
        var sleep: [DayKey: Double] = [:]
        for (day, checkIn) in model.checkIns where day < today && day >= start {
            if let hours = checkIn.sleepHours { sleep[day] = hours }
        }

        return VStack(alignment: .leading, spacing: GT.Spacing.s) {
            SectionHeader(title: "Prévisions", subtitle: "Scénarios sur tes habitudes, jamais sur tes cheveux")
            ForecastCard(title: "Régularité dans 30 jours", unit: .percent,
                         result: forecaster.project(metricName: "Régularité", observations: regularity, today: yesterday,
                                                    horizonDays: 30, valueRange: 0...1, target: 0.8),
                         targetLabel: "80 %")
            ForecastCard(title: "Sommeil dans 30 jours", unit: .hours,
                         result: forecaster.project(metricName: "Sommeil", observations: sleep, today: yesterday,
                                                    horizonDays: 30, valueRange: 0...14, target: 7),
                         targetLabel: "7 h")
        }
    }
}

private struct ForecastCard: View {
    enum Unit { case percent, hours }

    let title: String
    let unit: Unit
    let result: ForecastResult
    let targetLabel: String

    var body: some View {
        GTCard {
            Text(title).font(.headline)
            switch result {
            case .insufficientData(let reason):
                Label(ForecastResult.insufficientDataTitle, systemImage: "hourglass")
                    .font(.subheadline.weight(.medium))
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .projection(let projection):
                HStack(alignment: .firstTextBaseline, spacing: GT.Spacing.s) {
                    Text(format(projection.currentLevel))
                        .font(.title2.weight(.semibold).monospacedDigit())
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("vers")
                    Text(format(projection.projectedLevel))
                        .font(.title2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.gtGrowth)
                }
                Text("Fourchette probable : \(format(projection.lowerBound)) à \(format(projection.upperBound)) (à 95 %).")
                    .font(.subheadline)
                if let days = projection.daysToTarget {
                    Text(days == 0 ? "Objectif de \(targetLabel) déjà atteint en moyenne."
                         : "À ce rythme, objectif de \(targetLabel) atteint dans environ \(days) jours.")
                        .font(.subheadline)
                }
                DisclosureGroup("Hypothèses") {
                    VStack(alignment: .leading, spacing: GT.Spacing.xxs) {
                        ForEach(projection.assumptions, id: \.self) {
                            Label($0, systemImage: "info.circle").font(.footnote)
                        }
                        Text("Calcul : régression linéaire sur \(projection.observedDays) jours renseignés.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, GT.Spacing.xxs)
                }
                .font(.subheadline)
            }
        }
    }

    private func format(_ value: Double) -> String {
        switch unit {
        case .percent: value.formatted(.percent.precision(.fractionLength(0)))
        case .hours: value.formatted(.number.precision(.fractionLength(1))) + " h"
        }
    }
}

private struct UpcomingCard: View {
    @Environment(AppModel.self) private var model
    let period: ProgressPeriod
    let today: DayKey

    struct Event: Identifiable {
        let day: DayKey
        let title: String
        let symbol: String
        var id: String { "\(day)-\(title)" }
    }

    var body: some View {
        let horizon = today.adding(days: max(period.rawValue, 30))
        let photos = PhotoSchedule.upcoming(lastPhoto: model.lastPhotoDay, frequency: model.profile?.photoFrequency ?? .everyFourWeeks,
                                            today: today, through: horizon)
            .map { Event(day: $0, title: "Photos de suivi", symbol: "camera") }
        let milestones = Roadmap.milestones(programStart: model.programStart, today: today)
            .filter { $0.day > today && $0.day <= horizon }
            .map { Event(day: $0.day, title: $0.title, symbol: $0.symbol) }
        let events = (photos + milestones).sorted { $0.day < $1.day }

        GTCard {
            SectionHeader(title: "À venir")
            if events.isEmpty {
                Text("Rien de prévu sur cette période.").foregroundStyle(.secondary)
            }
            ForEach(events) { event in
                HStack {
                    Label(event.title, systemImage: event.symbol)
                    Spacer()
                    Text(event.day.date().formatted(.dateTime.day().month(.abbreviated)))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .font(.subheadline)
            }
        }
    }
}

private struct RoadmapCard: View {
    @Environment(AppModel.self) private var model
    let today: DayKey

    var body: some View {
        GTCard {
            SectionHeader(title: "Ta feuille de route", subtitle: "Des étapes de suivi, pas des promesses de résultat")
            ForEach(Roadmap.milestones(programStart: model.programStart, today: today)) { milestone in
                HStack(alignment: .top, spacing: GT.Spacing.s) {
                    Image(systemName: milestone.status == .past ? "checkmark.circle.fill" : milestone.symbol)
                        .font(.title3)
                        .foregroundStyle(milestone.status == .upcoming ? Color.secondary : Color.gtGrowth)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(milestone.title).font(.subheadline.weight(.semibold))
                            if milestone.status == .current {
                                Text("En cours")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.gtGrowth.opacity(0.15), in: .capsule)
                                    .foregroundStyle(Color.gtGrowth)
                            }
                        }
                        Text(milestone.day.date().formatted(date: .long, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(milestone.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

#Preview("Progrès") {
    ProgressTabView()
        .environment(AppModel.preview(withProfile: true))
}
