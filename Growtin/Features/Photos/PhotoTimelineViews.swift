import GrowtinCore
import SwiftUI

enum PhotoRoute: Hashable {
    case zone(PhotoZone)
    case photo(UUID)
    case compare(before: UUID, after: UUID)
}

/// Carte « Suivi photo » de l'onglet Progrès.
struct PhotoTrackingCard: View {
    @Environment(AppModel.self) private var model
    let today: DayKey
    let onStartSession: () -> Void

    var body: some View {
        let frequency = model.profile?.photoFrequency ?? .everyFourWeeks
        let next = PhotoSchedule.nextDue(lastPhoto: model.lastPhotoDay, frequency: frequency, today: today)
        GTCard {
            SectionHeader(title: "Suivi photo",
                          subtitle: next <= today ? "Une série de photos est conseillée aujourd'hui"
                                                  : "Prochaine série le \(next.date().formatted(date: .long, time: .omitted))")
            if model.photos.isEmpty {
                Text("Prends tes photos de référence : elles serviront de point de comparaison dans quelques mois.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.photoZones) { zone in
                    let photos = model.photos(for: zone)
                    NavigationLink(value: PhotoRoute.zone(zone)) {
                        HStack(spacing: GT.Spacing.s) {
                            if let latest = photos.last {
                                PhotoThumbnail(entry: latest, size: 44)
                            } else {
                                Image(systemName: zone.symbol)
                                    .frame(width: 44, height: 58)
                                    .background(Color.gtSurfaceRaised, in: .rect(cornerRadius: GT.Radius.small))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(zone.label).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                Text(photos.isEmpty ? "Aucune photo" : "\(photos.count) photo\(photos.count > 1 ? "s" : "") · dernière le \(photos.last!.takenAt.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Button(action: onStartSession) {
                Label(model.photos.isEmpty ? "Prendre mes photos de référence" : "Nouvelle série de photos", systemImage: "camera")
                    .frame(maxWidth: .infinity)
            }
            .gtProminentButton()
            .controlSize(.large)
        }
    }
}

/// Toutes les photos d'une zone, avec sélection de deux photos à comparer.
struct ZoneTimelineView: View {
    @Environment(AppModel.self) private var model
    let zone: PhotoZone
    @State private var selection: [UUID] = []
    @State private var isSelecting = false
    private let columns = [GridItem(.adaptive(minimum: 100), spacing: GT.Spacing.s)]

    var body: some View {
        let photos = model.photos(for: zone)
        ScrollView {
            VStack(alignment: .leading, spacing: GT.Spacing.m) {
                if photos.isEmpty {
                    ContentUnavailableView("Aucune photo", systemImage: "camera",
                                           description: Text("Les photos de cette zone apparaîtront ici."))
                } else {
                    if let pair = PhotoTimeline.defaultComparison(model.photos, zone: zone), !isSelecting {
                        NavigationLink(value: PhotoRoute.compare(before: pair.before.id, after: pair.after.id)) {
                            Label("Comparer la première et la dernière photo", systemImage: "rectangle.split.2x1")
                                .frame(maxWidth: .infinity)
                        }
                        .gtProminentButton()
                        .controlSize(.large)
                    }
                    if isSelecting {
                        Text(selection.count < 2 ? "Choisis deux photos à comparer (\(selection.count)/2)" : "Deux photos sélectionnées")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if selection.count == 2 {
                            NavigationLink(value: PhotoRoute.compare(before: selection[0], after: selection[1])) {
                                Label("Comparer", systemImage: "rectangle.split.2x1").frame(maxWidth: .infinity)
                            }
                            .gtProminentButton()
                            .controlSize(.large)
                        }
                    }
                    LazyVGrid(columns: columns, spacing: GT.Spacing.m) {
                        ForEach(photos.reversed()) { entry in
                            cell(entry)
                        }
                    }
                }
            }
            .padding(GT.Spacing.m)
        }
        .background(Color.gtBackground)
        .navigationTitle(zone.label)
        .toolbar {
            if photos.count >= 2 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSelecting ? "Annuler" : "Choisir") {
                        isSelecting.toggle()
                        selection = []
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ entry: PhotoEntry) -> some View {
        let isSelected = selection.contains(entry.id)
        let content = VStack(spacing: GT.Spacing.xxs) {
            PhotoThumbnail(entry: entry, size: 100)
                .overlay(alignment: .topTrailing) {
                    if isSelecting {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(.white, isSelected ? Color.gtGrowth : Color.black.opacity(0.3))
                            .padding(6)
                    }
                }
            Text(entry.takenAt.formatted(date: .abbreviated, time: .omitted))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if isSelecting {
            Button {
                if isSelected {
                    selection.removeAll { $0 == entry.id }
                } else if selection.count < 2 {
                    selection.append(entry.id)
                }
            } label: { content }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            NavigationLink(value: PhotoRoute.photo(entry.id)) { content }
                .buttonStyle(.plain)
        }
    }
}

struct PhotoDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let entry: PhotoEntry
    @State private var confirmingDeletion = false

    var body: some View {
        List {
            Section {
                StoredPhotoView(entry: entry)
                    .frame(maxWidth: .infinity, minHeight: 300)
                    .clipShape(.rect(cornerRadius: GT.Radius.small))
                    .listRowInsets(EdgeInsets())
            }
            Section("Informations") {
                LabeledContent("Date", value: entry.takenAt.formatted(date: .long, time: .shortened))
                LabeledContent("Source", value: entry.camera.label)
                if let quality = entry.quality {
                    let assessment = ImageQualityAnalyzer.assess(quality)
                    LabeledContent("Qualité technique", value: assessment.level.label)
                }
            }
            Section("Conditions") {
                LabeledContent("Cheveux secs", value: entry.conditions.dryHair ? "Oui" : "Non")
                LabeledContent("Coiffage habituel", value: entry.conditions.usualStyling ? "Oui" : "Non")
                LabeledContent("Sans produit", value: entry.conditions.noProduct ? "Oui" : "Non")
                LabeledContent("Lumière", value: entry.conditions.lighting.label)
            }
            Section {
                Button("Supprimer cette photo", systemImage: "trash", role: .destructive) { confirmingDeletion = true }
            }
        }
        .navigationTitle(entry.zone.label)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Supprimer cette photo ?", isPresented: $confirmingDeletion, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                model.deletePhoto(entry)
                dismiss()
            }
        } message: {
            Text("La photo sera définitivement effacée de ton iPhone.")
        }
    }
}

/// Comparaison visuelle de deux photos : curseur, superposition ou côte à côte.
struct PhotoCompareView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case slider = "Curseur", overlay = "Superposition", sideBySide = "Côte à côte"
        var id: String { rawValue }
    }

    let before: PhotoEntry
    let after: PhotoEntry
    @State private var mode: Mode = .slider
    @State private var position = 0.5
    @State private var opacity = 0.5

    init(first: PhotoEntry, second: PhotoEntry) {
        if first.takenAt <= second.takenAt {
            before = first
            after = second
        } else {
            before = second
            after = first
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: GT.Spacing.m) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                comparison
                    .aspectRatio(3 / 4, contentMode: .fit)
                    .clipShape(.rect(cornerRadius: GT.Radius.card))

                HStack {
                    dateLabel("Avant", before)
                    Spacer()
                    dateLabel("Après", after)
                }

                switch mode {
                case .slider:
                    Slider(value: $position, in: 0...1)
                        .accessibilityLabel("Position du curseur de comparaison")
                case .overlay:
                    Slider(value: $opacity, in: 0...1)
                        .accessibilityLabel("Transparence de la photo la plus récente")
                case .sideBySide:
                    EmptyView()
                }

                ComparabilityCard(report: ComparabilityAnalyzer.compare(before, after))
            }
            .padding(GT.Spacing.m)
        }
        .background(Color.gtBackground)
        .navigationTitle(before.zone.label)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var comparison: some View {
        switch mode {
        case .slider:
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    StoredPhotoView(entry: after, contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                    StoredPhotoView(entry: before, contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .mask(alignment: .leading) {
                            Rectangle().frame(width: proxy.size.width * position)
                        }
                    Rectangle()
                        .fill(.white)
                        .frame(width: 3)
                        .shadow(radius: 3)
                        .overlay {
                            Image(systemName: "arrow.left.and.right")
                                .font(.footnote.weight(.bold))
                                .padding(10)
                                .glassEffect(.regular, in: .circle)
                        }
                        .offset(x: proxy.size.width * position - 1.5)
                }
                .contentShape(.rect)
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    position = min(max(value.location.x / proxy.size.width, 0), 1)
                })
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Comparaison avant après, curseur à \(Int(position * 100)) pour cent")
        case .overlay:
            ZStack {
                StoredPhotoView(entry: before, contentMode: .fill)
                StoredPhotoView(entry: after, contentMode: .fill).opacity(opacity)
            }
            .clipped()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Superposition des deux photos")
        case .sideBySide:
            HStack(spacing: 2) {
                StoredPhotoView(entry: before, contentMode: .fill).clipped()
                StoredPhotoView(entry: after, contentMode: .fill).clipped()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Les deux photos côte à côte")
        }
    }

    private func dateLabel(_ title: String, _ entry: PhotoEntry) -> some View {
        VStack(alignment: title == "Avant" ? .leading : .trailing, spacing: 2) {
            Text(title).gtEyebrowStyle()
            Text(entry.takenAt.formatted(date: .abbreviated, time: .omitted)).font(.subheadline.weight(.semibold))
        }
    }
}
