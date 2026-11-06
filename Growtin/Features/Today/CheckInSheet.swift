import GrowtinCore
import SwiftUI

/// Bilan du jour : tout est facultatif, l'objectif est de garder une trace sans pression.
struct CheckInSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let day: DayKey

    @State private var logSleep: Bool
    @State private var sleepHours: Double
    @State private var stress: Int?
    @State private var shedding: SheddingPerception?
    @State private var note: String

    init(day: DayKey, existing: DailyCheckIn?) {
        self.day = day
        _logSleep = State(initialValue: existing?.sleepHours != nil)
        _sleepHours = State(initialValue: existing?.sleepHours ?? 7)
        _stress = State(initialValue: existing?.stress)
        _shedding = State(initialValue: existing?.shedding)
        _note = State(initialValue: existing?.note ?? "")
    }

    private var draft: DailyCheckIn {
        DailyCheckIn(day: day, sleepHours: logSleep ? sleepHours : nil, stress: stress, shedding: shedding, note: note)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Renseigner mon sommeil", isOn: $logSleep.animation())
                    if logSleep {
                        Stepper(value: $sleepHours, in: 0...14, step: 0.5) {
                            Text("\(sleepHours.formatted()) h cette nuit")
                                .monospacedDigit()
                        }
                    }
                } header: {
                    Text("Sommeil")
                }

                Section {
                    Picker("Stress ressenti", selection: $stress) {
                        Text("—").tag(Int?.none)
                        ForEach(1...5, id: \.self) { Text("\($0)").tag(Optional($0)) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Stress ressenti")
                } footer: {
                    Text("1 : très calme · 5 : très stressé")
                }

                Section("Chute perçue") {
                    Picker("Chute perçue", selection: $shedding) {
                        Text("Non renseigné").tag(SheddingPerception?.none)
                        ForEach(SheddingPerception.allCases) { Text($0.label).tag(Optional($0)) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    TextField("Ce que tu as remarqué aujourd'hui…", text: $note, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("Note libre")
                } footer: {
                    Text("Une observation isolée n'a pas de valeur médicale. C'est la tendance sur plusieurs semaines qui compte.")
                }

                let alerts = SafetyScreener().assess(text: note)
                if !alerts.isEmpty {
                    Section {
                        ForEach(alerts) { SafetyBanner(alert: $0) }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Bilan du jour")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer", systemImage: "checkmark") {
                        model.saveCheckIn(draft)
                        dismiss()
                    }
                    .buttonStyle(.glassProminent)
                }
            }
        }
    }
}
