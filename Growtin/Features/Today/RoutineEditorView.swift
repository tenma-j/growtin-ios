import GrowtinCore
import SwiftUI
import UIKit

struct RoutineEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var showingCustomHabit = false

    private var availableTemplates: [HabitTemplate] {
        let active = Set(model.activeRoutine.compactMap(\.templateID))
        return HabitCatalog.all.filter { !active.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(DaySlot.allCases) { slot in
                    let items = model.activeRoutine.filter { $0.slot == slot }
                    if !items.isEmpty {
                        Section(slot.label) {
                            ForEach(items) { item in
                                NavigationLink {
                                    RoutineItemEditor(item: item)
                                } label: {
                                    LabeledContent {
                                        Text(item.timeLabel).monospacedDigit()
                                    } label: {
                                        Label(item.title, systemImage: item.symbol)
                                    }
                                }
                                .swipeActions {
                                    Button("Retirer", systemImage: "trash", role: .destructive) { model.remove(item) }
                                }
                            }
                        }
                    }
                }

                Section {
                    ForEach(availableTemplates) { template in
                        Button {
                            model.addHabit(template: template)
                        } label: {
                            HStack {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(template.title).foregroundStyle(.primary)
                                        Text(template.detail).font(.footnote).foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: template.symbol)
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill").foregroundStyle(Color.gtGrowth)
                            }
                        }
                    }
                    Button("Créer une habitude personnelle", systemImage: "square.and.pencil") { showingCustomHabit = true }
                } header: {
                    Text("Ajouter")
                } footer: {
                    Text("Une routine courte et réaliste est plus facile à tenir. Retirer une habitude ne supprime pas ton historique.")
                }
            }
            .navigationTitle("Ma routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé", systemImage: "checkmark") { dismiss() }
                }
            }
            .sheet(isPresented: $showingCustomHabit) {
                CustomHabitSheet()
                    .presentationDetents([.medium])
            }
        }
    }
}

struct RoutineItemEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var item: RoutineItem
    @State private var showingDeniedAlert = false
    private let original: RoutineItem

    init(item: RoutineItem) {
        original = item
        _item = State(initialValue: item)
    }

    private var time: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: item.minuteOfDay / 60, minute: item.minuteOfDay % 60, second: 0, of: .now) ?? .now
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                item.minuteOfDay = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            })
    }

    var body: some View {
        Form {
            Section {
                if item.templateID == nil {
                    TextField("Nom", text: $item.title)
                } else {
                    LabeledContent("Habitude", value: item.title)
                }
                DatePicker("Heure", selection: time, displayedComponents: .hourAndMinute)
            }
            Section {
                Toggle("Rappel quotidien", isOn: Binding(get: { item.reminderEnabled }, set: { enable(reminder: $0) }))
            } footer: {
                Text("Un rappel discret, à l'heure choisie. Tu peux le désactiver à tout moment.")
            }
            if let reason = item.reason {
                Section("Pourquoi cette habitude") { Text(reason) }
            }
            Section {
                Button("Retirer de ma routine", role: .destructive) {
                    item.removedOn = DayKey(.now)
                    model.remove(item)
                    dismiss()
                }
            }
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            if item.isActive, item != original { model.update(item) }
        }
        .alert("Notifications désactivées", isPresented: $showingDeniedAlert) {
            Button("Ouvrir les Réglages") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            Button("Plus tard", role: .cancel) {}
        } message: {
            Text("Pour recevoir ce rappel, autorise les notifications de Growtin' dans les Réglages de l'iPhone.")
        }
    }

    /// L'autorisation n'est demandée qu'au moment où l'utilisateur active son premier rappel.
    private func enable(reminder: Bool) {
        guard reminder else {
            item.reminderEnabled = false
            return
        }
        Task {
            switch await model.notifications.authorizationStatus() {
            case .authorized:
                item.reminderEnabled = true
            case .notDetermined:
                item.reminderEnabled = await model.notifications.requestAuthorization()
                if !item.reminderEnabled { showingDeniedAlert = true }
            case .denied:
                showingDeniedAlert = true
            }
        }
    }
}

private struct CustomHabitSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var time = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now

    var body: some View {
        NavigationStack {
            Form {
                TextField("Par exemple : boire un grand verre d'eau", text: $title)
                DatePicker("Heure", selection: $time, displayedComponents: .hourAndMinute)
            }
            .navigationTitle("Nouvelle habitude")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter", systemImage: "checkmark") {
                        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
                        model.addCustomHabit(title: title, minuteOfDay: (components.hour ?? 0) * 60 + (components.minute ?? 0))
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
