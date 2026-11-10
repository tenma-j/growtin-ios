import AVFoundation
import GrowtinCore
import PhotosUI
import SwiftUI
import UIKit

/// Séance photo guidée : conseils, puis capture et vérification zone par zone.
struct PhotoSessionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    enum Phase: Equatable {
        case intro
        case capture(index: Int)
        case review(index: Int, draft: PhotoDraft)
        case done
    }

    @State private var phase: Phase
    @State private var zones: [PhotoZone] = []
    @State private var savedCount = 0

    init(startAtCapture: Bool = false) {
        _phase = State(initialValue: startAtCapture ? .capture(index: 0) : .intro)
    }

    var body: some View {
        Group {
            switch phase {
            case .intro:
                PhotoSessionIntro(zones: $zones, onStart: { phase = .capture(index: 0) }, onClose: { dismiss() })
            case .capture(let index):
                if zones.indices.contains(index) {
                    CaptureView(zone: zones[index], step: index + 1, stepCount: zones.count,
                                previous: model.photos(for: zones[index]).last,
                                onCaptured: { phase = .review(index: index, draft: $0) },
                                onSkip: { advance(from: index) },
                                onClose: { dismiss() })
                        .id(index)
                }
            case .review(let index, let draft):
                PhotoReviewView(draft: draft, previous: model.photos(for: zones[index]).last,
                                onRetake: { phase = .capture(index: index) },
                                onSave: { conditions in
                                    if model.addPhoto(jpegData: draft.jpegData, zone: draft.zone, camera: draft.camera,
                                                      quality: draft.quality, conditions: conditions, framing: draft.framing) {
                                        savedCount += 1
                                        advance(from: index)
                                    }
                                })
            case .done:
                PhotoSessionDone(savedCount: savedCount, onClose: { dismiss() })
            }
        }
        .onAppear {
            if zones.isEmpty { zones = model.photoZones }
        }
    }

    private func advance(from index: Int) {
        phase = index + 1 < zones.count ? .capture(index: index + 1) : .done
    }
}

/// Photo prise, en attente de validation.
struct PhotoDraft: Equatable {
    let id = UUID()
    let zone: PhotoZone
    let camera: CameraPosition
    let jpegData: Data
    let image: UIImage
    var quality: ImageQuality?
    var framing: FramingInfo

    static func == (lhs: PhotoDraft, rhs: PhotoDraft) -> Bool { lhs.id == rhs.id }

    /// Prépare une photo : redressement, réduction, suppression des métadonnées et analyse technique.
    static func make(from data: Data, zone: PhotoZone, camera: CameraPosition, pitch: Double?, roll: Double?) async -> PhotoDraft? {
        guard let original = UIImage(data: data),
              let normalized = PhotoAnalysis.normalizedJPEG(from: original, mirrored: camera == .front) else { return nil }
        let quality = PhotoAnalysis.quality(of: normalized.image)
        let face = await PhotoAnalysis.faceFraming(in: normalized.image)
        let framing = FramingInfo(faceCenterX: face?.centerX, faceCenterY: face?.centerY, faceWidth: face?.width,
                                  devicePitch: pitch, deviceRoll: roll)
        return PhotoDraft(zone: zone, camera: camera, jpegData: normalized.data, image: normalized.image,
                          quality: quality, framing: framing)
    }
}

// MARK: - Introduction

private struct PhotoSessionIntro: View {
    @Binding var zones: [PhotoZone]
    let onStart: () -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: GT.Spacing.l) {
                    StepHeader(eyebrow: "Suivi photo", title: "Des photos comparables",
                               subtitle: "Des conditions identiques d'une fois à l'autre comptent plus que la qualité de l'appareil.")
                    GTCard {
                        tip("sun.max", "Même lumière", "Même pièce, même heure, de préférence face à une fenêtre. Évite la lumière directe au-dessus de la tête.")
                        tip("drop", "Cheveux secs", "Des cheveux mouillés paraissent nettement moins denses.")
                        tip("comb", "Coiffage habituel", "Sans produit coiffant, coiffés comme d'habitude.")
                        tip("viewfinder", "Même cadrage", "Suis le guide à l'écran. La photo précédente peut s'afficher en transparence.")
                    }
                    VStack(alignment: .leading, spacing: GT.Spacing.s) {
                        Text("Zones à photographier").font(.headline)
                        MultiChoiceChips(options: Array(PhotoZone.allCases),
                                         selection: Binding(get: { Set(zones) },
                                                            set: { new in zones = PhotoZone.allCases.filter(new.contains) }),
                                         title: \.label, symbol: { $0.symbol })
                    }
                    PrivacyNote(text: "Tes photos restent sur ton iPhone, chiffrées. Elles ne sont envoyées à aucun serveur et ne sont jamais analysées par une IA.")
                }
                .padding(.horizontal, GT.Spacing.l)
                .padding(.bottom, GT.Spacing.xl)
            }
            .background(Color.gtBackground)
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: "Commencer (\(zones.count) photo\(zones.count > 1 ? "s" : ""))", systemImage: "camera",
                              isEnabled: !zones.isEmpty, action: onStart)
                    .padding(.horizontal, GT.Spacing.l)
                    .padding(.bottom, GT.Spacing.s)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer", systemImage: "xmark", action: onClose)
                }
            }
        }
    }

    private func tip(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: GT.Spacing.s) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.gtGrowth)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Capture

private struct CaptureView: View {
    let zone: PhotoZone
    let step: Int
    let stepCount: Int
    let previous: PhotoEntry?
    let onCaptured: (PhotoDraft) -> Void
    let onSkip: () -> Void
    let onClose: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var camera: CameraController
    @State private var motion = MotionMonitor()
    @State private var showGhost = true
    @State private var ghostOpacity = 0.35
    @State private var ghostImage: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var isProcessing = false

    init(zone: PhotoZone, step: Int, stepCount: Int, previous: PhotoEntry?,
         onCaptured: @escaping (PhotoDraft) -> Void, onSkip: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.zone = zone
        self.step = step
        self.stepCount = stepCount
        self.previous = previous
        self.onCaptured = onCaptured
        self.onSkip = onSkip
        self.onClose = onClose
        let position: AVCaptureDevice.Position = (previous?.camera ?? zone.preferredCamera) == .back ? .back : .front
        _camera = State(initialValue: CameraController(position: position))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch camera.status {
            case .running, .idle:
                CameraPreview(session: camera.cameraSession.session)
                    .ignoresSafeArea()
                if showGhost, let ghostImage {
                    Image(uiImage: ghostImage)
                        .resizable()
                        .scaledToFill()
                        .opacity(ghostOpacity)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                FramingGuide(zone: zone).ignoresSafeArea()
            case .unavailable, .denied, .failed:
                CameraUnavailableView(status: camera.status, openSettings: {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                })
            }
            overlay
            if isProcessing {
                ProgressView("Analyse de la photo…")
                    .padding()
                    .glassEffect(.regular, in: .rect(cornerRadius: GT.Radius.card))
            }
        }
        .task {
            ghostImage = previous.flatMap { model.photoStore.image(fileName: $0.fileName) }
            motion.start()
            await camera.start()
        }
        .onDisappear {
            camera.stop()
            motion.stop()
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await process(data, source: .library)
                }
                pickerItem = nil
            }
        }
    }

    private var overlay: some View {
        VStack(spacing: GT.Spacing.s) {
            HStack {
                Button("Fermer", systemImage: "xmark", action: onClose)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                Spacer()
                VStack(spacing: 2) {
                    Text(zone.label).font(.headline)
                    Text("Photo \(step) sur \(stepCount)").font(.caption)
                }
                .foregroundStyle(.white)
                .shadow(radius: 4)
                Spacer()
                Button("Passer cette zone", systemImage: "forward", action: onSkip)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
            }
            if camera.status == .running {
                HStack(spacing: GT.Spacing.xs) {
                    if let brightness = camera.liveBrightness {
                        let ok = brightness >= ImageQualityAnalyzer.Thresholds.tooDark && brightness <= ImageQualityAnalyzer.Thresholds.tooBright
                        StatusPill(text: ok ? "Lumière correcte" : (brightness < 0.5 ? "Trop sombre" : "Trop lumineux"),
                                   systemImage: "sun.max", isOK: ok)
                    }
                    if let angle = angleStatus {
                        StatusPill(text: angle.text, systemImage: "level", isOK: angle.ok)
                    }
                }
            }
            Spacer()
            Text(zone.instruction)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .padding(GT.Spacing.m)
                .glassEffect(.regular, in: .rect(cornerRadius: GT.Radius.card))
            if ghostImage != nil, camera.status == .running {
                HStack {
                    Toggle(isOn: $showGhost) { Text("Photo précédente") }
                        .toggleStyle(.button)
                        .buttonStyle(.glass)
                    if showGhost {
                        Slider(value: $ghostOpacity, in: 0.1...0.7)
                            .frame(maxWidth: 160)
                            .accessibilityLabel("Transparence de la photo précédente")
                    }
                }
            }
            HStack(alignment: .center) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.title3)
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Importer depuis Photos")
                Spacer()
                Button {
                    Task { await shoot() }
                } label: {
                    Circle()
                        .strokeBorder(.white, lineWidth: 4)
                        .background(Circle().fill(.white.opacity(0.9)).padding(6))
                        .frame(width: 76, height: 76)
                }
                .buttonStyle(.plain)
                .disabled(camera.status != .running || camera.isCapturing || isProcessing)
                .accessibilityLabel("Prendre la photo")
                Spacer()
                Button("Changer de caméra", systemImage: "arrow.triangle.2.circlepath.camera") {
                    Task { await camera.flip() }
                }
                .labelStyle(.iconOnly)
                .font(.title3)
                .frame(width: 52, height: 52)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .disabled(camera.status != .running)
            }
            .padding(.horizontal, GT.Spacing.s)
        }
        .padding(GT.Spacing.m)
    }

    /// Compare l'inclinaison actuelle à celle de la photo précédente de la même zone.
    private var angleStatus: (text: String, ok: Bool)? {
        guard let pitch = motion.pitch, let roll = motion.roll,
              let previousPitch = previous?.framing.devicePitch, let previousRoll = previous?.framing.deviceRoll else { return nil }
        let ok = abs(pitch - previousPitch) <= 8 && abs(roll - previousRoll) <= 8
        return (ok ? "Même angle que la dernière fois" : "Angle différent", ok)
    }

    private func shoot() async {
        guard let data = await camera.capture() else { return }
        await process(data, source: camera.isFrontCamera ? .front : .back)
    }

    private func process(_ data: Data, source: CameraPosition) async {
        isProcessing = true
        defer { isProcessing = false }
        let pitch = source == .library ? nil : motion.pitch
        let roll = source == .library ? nil : motion.roll
        if let draft = await PhotoDraft.make(from: data, zone: zone, camera: source, pitch: pitch, roll: roll) {
            onCaptured(draft)
        }
    }
}

private struct CameraUnavailableView: View {
    let status: CameraController.Status
    let openSettings: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "camera.slash")
        } description: {
            Text(message)
        } actions: {
            if status == .denied {
                Button("Ouvrir les Réglages", action: openSettings)
                    .gtProminentButton()
            }
        }
        .foregroundStyle(.white)
    }

    private var title: String {
        switch status {
        case .denied: "Accès à l'appareil photo refusé"
        case .unavailable: "Appareil photo indisponible"
        default: "L'appareil photo n'a pas pu démarrer"
        }
    }

    private var message: String {
        switch status {
        case .denied: "Autorise l'appareil photo dans les Réglages, ou importe une photo depuis ta photothèque."
        case .unavailable: "Aucun appareil photo n'est disponible sur cet appareil. Tu peux importer une photo depuis ta photothèque."
        default: "Réessaie dans un instant, ou importe une photo depuis ta photothèque."
        }
    }
}

/// Aperçu vidéo AVFoundation.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

// MARK: - Vérification

private struct PhotoReviewView: View {
    let draft: PhotoDraft
    let previous: PhotoEntry?
    let onRetake: () -> Void
    let onSave: (CaptureConditions) -> Void
    @State private var conditions: CaptureConditions

    init(draft: PhotoDraft, previous: PhotoEntry?, onRetake: @escaping () -> Void, onSave: @escaping (CaptureConditions) -> Void) {
        self.draft = draft
        self.previous = previous
        self.onRetake = onRetake
        self.onSave = onSave
        var initial = previous?.conditions ?? CaptureConditions()
        initial.dryHair = true
        initial.usualStyling = true
        initial.noProduct = true
        _conditions = State(initialValue: initial)
    }

    private var assessment: QualityAssessment? { draft.quality.map(ImageQualityAnalyzer.assess) }

    private var comparability: ComparabilityReport? {
        guard let previous else { return nil }
        let candidate = PhotoEntry(zone: draft.zone, day: DayKey(.now), fileName: "", camera: draft.camera,
                                   quality: draft.quality, conditions: conditions, framing: draft.framing)
        return ComparabilityAnalyzer.compare(previous, candidate)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: GT.Spacing.l) {
                    Image(uiImage: draft.image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(.rect(cornerRadius: GT.Radius.card))
                        .frame(maxHeight: 360)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Photo \(draft.zone.label) qui vient d'être prise")

                    if let assessment {
                        GTCard {
                            Label(assessment.level.label, systemImage: assessment.level.symbol)
                                .font(.headline)
                                .foregroundStyle(assessment.level.tint)
                            if assessment.issues.isEmpty {
                                Text("Netteté et luminosité correctes.").font(.subheadline).foregroundStyle(.secondary)
                            }
                            ForEach(assessment.issues) { issue in
                                Label(issue.message, systemImage: "info.circle").font(.footnote)
                            }
                            Text("Ce contrôle porte uniquement sur la qualité technique de la photo.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    GTCard {
                        Text("Conditions de la photo").font(.headline)
                        Toggle("Cheveux secs", isOn: $conditions.dryHair)
                        Toggle("Coiffage habituel", isOn: $conditions.usualStyling)
                        Toggle("Sans produit coiffant", isOn: $conditions.noProduct)
                        Picker("Lumière", selection: $conditions.lighting) {
                            ForEach(LightingSource.allCases) { Text($0.label).tag($0) }
                        }
                    }

                    if let comparability {
                        ComparabilityCard(report: comparability)
                    }
                }
                .padding(GT.Spacing.m)
            }
            .background(Color.gtBackground)
            .navigationTitle(draft.zone.label)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: GT.Spacing.s) {
                    Button(action: onRetake) {
                        Label("Reprendre", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    PrimaryButton(title: "Enregistrer", systemImage: "checkmark") { onSave(conditions) }
                }
                .padding(.horizontal, GT.Spacing.m)
                .padding(.bottom, GT.Spacing.s)
            }
        }
    }
}

// MARK: - Fin

private struct PhotoSessionDone: View {
    @Environment(AppModel.self) private var model
    let savedCount: Int
    let onClose: () -> Void

    var body: some View {
        let frequency = model.profile?.photoFrequency ?? .everyFourWeeks
        let next = PhotoSchedule.nextDue(lastPhoto: model.lastPhotoDay, frequency: frequency, today: DayKey(.now))
        VStack(spacing: GT.Spacing.l) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.gtGrowth)
                .accessibilityHidden(true)
            Text(savedCount == 0 ? "Aucune photo enregistrée" : "\(savedCount) photo\(savedCount > 1 ? "s" : "") enregistrée\(savedCount > 1 ? "s" : "")")
                .font(.title2.weight(.bold))
            Text("Prochaine série conseillée : \(next.date().formatted(date: .long, time: .omitted)). Inutile de regarder tes cheveux chaque jour : les changements, quels qu'ils soient, se jugent sur plusieurs mois.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            PrimaryButton(title: "Terminer", action: onClose)
        }
        .padding(GT.Spacing.l)
        .background(Color.gtBackground)
    }
}
