import Combine
import GrowtinCore
import SwiftUI

/// Ce qui est présenté en plein écran ou en feuille depuis l'accueil.
enum TodayPresentation: Identifiable {
    case evidence(EvidenceCard, reason: String?)
    case breathing(RoutineItem)
    case scalpMassage(RoutineItem)
    case checkIn
    case editRoutine
    case settings

    var id: String {
        switch self {
        case .evidence(let card, _): "evidence-\(card.id)"
        case .breathing(let item): "breathing-\(item.id)"
        case .scalpMassage(let item): "massage-\(item.id)"
        case .checkIn: "check-in"
        case .editRoutine: "edit-routine"
        case .settings: "settings"
        }
    }
}

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var today = DayKey(.now)
    @State private var sheet: TodayPresentation?
    @State private var session: TodayPresentation?
    @State private var showingPhotoSession = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: GT.Spacing.l) {
                    ForEach(model.alerts(for: today)) { SafetyBanner(alert: $0) }
                    RegularityCard(today: today)
                    CheckInCard(checkIn: model.checkIns[today]) { sheet = .checkIn }
                    NextStepsCard(today: today) { showingPhotoSession = true }
                    routineSections
                    FootnoteText(text: WellnessNotice.short)
                }
                .padding(.horizontal, GT.Spacing.m)
                .padding(.bottom, GT.Spacing.xl)
            }
            .background(Color.gtBackground)
            .navigationTitle(Greeting.text(name: model.profile?.displayName))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Modifier ma routine", systemImage: "slider.horizontal.3") { sheet = .editRoutine }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Profil et réglages", systemImage: "person.crop.circle") { sheet = .settings }
                }
            }
            .sheet(item: $sheet) { presentation in
                switch presentation {
                case .evidence(let card, let reason):
                    EvidenceSheet(card: card, personalReason: reason, library: model.library)
                        .presentationDetents([.medium, .large])
                case .checkIn:
                    CheckInSheet(day: today, existing: model.checkIns[today])
                case .editRoutine:
                    RoutineEditorView()
                case .settings:
                    SettingsView()
                default:
                    EmptyView()
                }
            }
            .fullScreenCover(item: $session) { presentation in
                switch presentation {
                case .breathing(let item):
                    BreathingSessionView(minutes: item.template?.durationMinutes ?? 3) {
                        model.setCompleted(true, item: item, on: today)
                    }
                case .scalpMassage(let item):
                    ScalpMassageSessionView {
                        model.setCompleted(true, item: item, on: today)
                    }
                default:
                    EmptyView()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                today = DayKey(.now)
            }
            .task { presentDemoScreenIfNeeded() }
            .fullScreenCover(isPresented: $showingPhotoSession) { PhotoSessionView() }
        }
    }

    @ViewBuilder
    private var routineSections: some View {
        let items = model.activeRoutine
        if items.isEmpty {
            GTCard {
                ContentUnavailableView {
                    Label("Aucune habitude", systemImage: "checklist")
                } description: {
                    Text("Ta routine est vide. Ajoute une habitude pour commencer.")
                } actions: {
                    Button("Ajouter une habitude") { sheet = .editRoutine }
                        .buttonStyle(.glassProminent)
                }
            }
        } else {
            ForEach(DaySlot.allCases) { slot in
                let slotItems = items.filter { $0.slot == slot }
                if !slotItems.isEmpty {
                    VStack(alignment: .leading, spacing: GT.Spacing.s) {
                        Label(slot.label, systemImage: slot.symbol)
                            .gtEyebrowStyle()
                            .accessibilityAddTraits(.isHeader)
                        VStack(spacing: 0) {
                            ForEach(slotItems) { item in
                                RoutineRow(
                                    item: item,
                                    isCompleted: model.isCompleted(item, on: today),
                                    onToggle: { model.setCompleted(!model.isCompleted(item, on: today), item: item, on: today) },
                                    onStart: { start(item) },
                                    onInfo: infoAction(for: item))
                                if item.id != slotItems.last?.id {
                                    Divider().padding(.leading, 60)
                                }
                            }
                        }
                        .background(Color.gtSurface, in: .rect(cornerRadius: GT.Radius.card))
                    }
                }
            }
        }
    }

    /// Ouvre directement une feuille ou une séance pour les captures d'écran automatiques.
    private func presentDemoScreenIfNeeded() {
        switch DemoLaunch.screen {
        case "evidence":
            if let item = model.activeRoutine.first(where: { $0.template?.evidenceCard != nil }),
               let card = item.template?.evidenceCard {
                sheet = .evidence(card, reason: item.reason)
            }
        case "checkin": sheet = .checkIn
        case "settings": sheet = .settings
        case "editRoutine": sheet = .editRoutine
        case "breathing":
            if let item = model.activeRoutine.first(where: { $0.kind == .guidedBreathing }) { session = .breathing(item) }
        default: break
        }
    }

    private func infoAction(for item: RoutineItem) -> (() -> Void)? {
        guard let card = item.template?.evidenceCard else { return nil }
        return { sheet = .evidence(card, reason: item.reason) }
    }

    private func start(_ item: RoutineItem) {
        switch item.kind {
        case .guidedBreathing: session = .breathing(item)
        case .guidedScalpMassage: session = .scalpMassage(item)
        case .checkIn: sheet = .checkIn
        case .check: model.setCompleted(!model.isCompleted(item, on: today), item: item, on: today)
        }
    }
}

#Preview("Aujourd'hui") {
    TodayView()
        .environment(AppModel.preview(withProfile: true))
}
