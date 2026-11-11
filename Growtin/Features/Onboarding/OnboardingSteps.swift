import GrowtinCore
import SwiftUI

// MARK: - 1. Bienvenue

struct WelcomeStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: GT.Spacing.l) {
            StepHeader(
                eyebrow: "Growtin'",
                title: "De meilleures habitudes, cheveu par cheveu.",
                subtitle: "Growtin' t'accompagne chaque jour : une routine adaptée à ta situation, un suivi photo régulier et des informations fondées sur des sources scientifiques vérifiées.")

            GTCard {
                Text("Avant de commencer")
                    .font(.headline)
                Text("Growtin' est une application de bien-être. Elle ne diagnostique, ne traite et ne prévient aucune maladie, et ne promet aucune repousse. En cas de chute brutale, de plaques, de douleur ou d'inflammation, consulte un médecin ou un dermatologue.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Toggle(isOn: $model.disclaimerAccepted) {
                    Text("J'ai compris que Growtin' est une application de bien-être et non un dispositif médical.")
                        .font(.subheadline.weight(.medium))
                }
                .toggleStyle(GTCheckboxToggleStyle())
                .padding(.top, GT.Spacing.xs)
            }

            PrivacyNote(text: "Tes réponses restent sur ton iPhone. Tu pourras les modifier ou les supprimer à tout moment.")
        }
    }
}

/// Case à cocher accessible, utilisée pour les consentements explicites.
struct GTCheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: GT.Spacing.s) {
                Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(configuration.isOn ? Color.gtInk : Color.secondary)
                    .accessibilityHidden(true)
                configuration.label
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: configuration.isOn)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? "Coché" : "Non coché")
    }
}

// MARK: - 2. Parlons de toi

struct AboutYouStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: GT.Spacing.m) {
            StepHeader(title: "Parlons de toi",
                       subtitle: "Ces informations servent uniquement à adapter ton programme et les contenus proposés.")

            FieldLabel(text: "Comment veux-tu qu'on t'appelle ? (facultatif)")
            TextField("Prénom", text: Binding(get: { model.draft.firstName ?? "" }, set: { model.draft.firstName = $0 }))
                .textContentType(.givenName)
                .textInputAutocapitalization(.words)
                .padding(GT.Spacing.m)
                .background(Color.gtSurface, in: .rect(cornerRadius: GT.Radius.control))

            FieldLabel(text: "Sexe")
            HStack(spacing: GT.Spacing.s) {
                ForEach([BiologicalSex.male, .female]) { option in
                    ChoiceRow(title: option.label, isSelected: model.sex == option) { model.sex = option }
                }
            }
            ChoiceRow(title: BiologicalSex.unspecified.label, isSelected: model.sex == .unspecified) { model.sex = .unspecified }
            Text("Les mécanismes et les échelles de suivi diffèrent selon le sexe. Cette information n'est utilisée qu'à cette fin.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            FieldLabel(text: "Âge")
            ValueSlider(value: Binding(get: { Double(model.draft.age) }, set: { model.draft.age = Int($0) }),
                        range: 16...90, unit: "ans", accessibilityName: "Âge")

            Toggle("Ajouter ma taille et mon poids", isOn: $model.shareBodyMeasures.animation())
                .font(.body.weight(.medium))
                .padding(.top, GT.Spacing.s)
            if model.shareBodyMeasures {
                Text("Facultatif. Le poids sert uniquement à calculer ton repère protéique de référence (EFSA).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                FieldLabel(text: "Taille")
                ValueSlider(value: Binding(get: { Double(model.draft.heightCm ?? 170) }, set: { model.draft.heightCm = Int($0) }),
                            range: 140...210, unit: "cm", accessibilityName: "Taille")
                FieldLabel(text: "Poids")
                ValueSlider(value: Binding(get: { Double(model.draft.weightKg ?? 70) }, set: { model.draft.weightKg = Int($0) }),
                            range: 40...160, unit: "kg", accessibilityName: "Poids")
            }
        }
        .onChange(of: model.shareBodyMeasures) { _, isOn in
            if isOn {
                model.draft.heightCm = model.draft.heightCm ?? 170
                model.draft.weightKg = model.draft.weightKg ?? 70
            }
        }
    }
}

struct ValueSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String
    let accessibilityName: String

    var body: some View {
        VStack(alignment: .trailing, spacing: GT.Spacing.xs) {
            Text("\(Int(value)) \(unit)")
                .font(.title3.weight(.semibold).monospacedDigit())
                .contentTransition(.numericText())
            Slider(value: $value, in: range, step: 1)
                .accessibilityLabel(accessibilityName)
                .accessibilityValue("\(Int(value)) \(unit)")
        }
    }
}

// MARK: - 3. Depuis quand ?

struct HistoryStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: GT.Spacing.m) {
            StepHeader(title: "Depuis quand ?",
                       subtitle: "La chronologie aide à situer ta situation. Une chute récente et brutale justifie un avis médical.")
            VStack(spacing: GT.Spacing.s) {
                ForEach(HairLossDuration.allCases) { option in
                    ChoiceRow(title: option.label, isSelected: model.duration == option) { model.duration = option }
                }
            }
            FieldLabel(text: "Déclencheurs perçus (plusieurs choix possibles)")
            MultiChoiceChips(options: Array(PerceivedTrigger.allCases), selection: $model.draft.triggers,
                             title: \.label, symbol: { $0.symbol }, exclusive: .unknown)
            if model.draft.triggers.contains(.other) {
                OtherDetailField(prompt: "Précise (ex. déménagement, changement de pilule…)", text: $model.draft.otherTriggers)
            }
            FieldLabel(text: "Antécédents familiaux de chute de cheveux")
            VStack(spacing: GT.Spacing.s) {
                ForEach(FamilyHistory.allCases) { option in
                    ChoiceRow(title: option.label, isSelected: model.draft.familyHistory == option) {
                        model.draft.familyHistory = option
                    }
                }
            }
        }
    }
}

// MARK: - 4. Stade auto-évalué

struct StageStep: View {
    @Bindable var model: OnboardingModel
    private let columns = [GridItem(.adaptive(minimum: 96), spacing: GT.Spacing.s)]

    var body: some View {
        let scale = model.draft.stage.scale
        VStack(alignment: .leading, spacing: GT.Spacing.m) {
            StepHeader(title: scale.name,
                       subtitle: "Choisis le schéma qui ressemble le plus à ta situation actuelle. C'est une auto-évaluation : Growtin' ne détermine jamais ton stade.")

            Picker("Échelle", selection: Binding(
                get: { scale },
                set: { model.draft.stage = SelfAssessedStage(scale: $0, stage: nil) })) {
                Text("Norwood").tag(HairStageScale.norwood)
                Text("Ludwig").tag(HairStageScale.ludwig)
            }
            .pickerStyle(.segmented)

            LazyVGrid(columns: columns, spacing: GT.Spacing.s) {
                ForEach(Array(scale.stages), id: \.self) { stage in
                    let isSelected = model.draft.stage.stage == stage
                    Button {
                        model.draft.stage = SelfAssessedStage(scale: scale, stage: stage)
                    } label: {
                        VStack(spacing: GT.Spacing.xs) {
                            StageIllustration(scale: scale, stage: stage)
                                .frame(height: 64)
                            Text("Stade \(stage)")
                                .font(.subheadline.weight(.medium))
                        }
                        .padding(GT.Spacing.s)
                        .frame(maxWidth: .infinity)
                        .background(Color.gtSurface, in: .rect(cornerRadius: GT.Radius.control))
                        .overlay {
                            RoundedRectangle(cornerRadius: GT.Radius.control)
                                .strokeBorder(isSelected ? Color.gtInk : .clear, lineWidth: 2)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Stade \(stage)")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            ChoiceRow(title: "Je ne sais pas", isSelected: model.draft.stage.stage == nil) {
                model.draft.stage = SelfAssessedStage(scale: scale, stage: nil)
            }
            Text("Norwood décrit le recul de la ligne frontale et du sommet, plus fréquent chez l'homme. Ludwig décrit l'affinement diffus autour de la raie, plus fréquent chez la femme.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 5. Zones concernées

struct ZonesStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: GT.Spacing.m) {
            StepHeader(title: "Zones concernées",
                       subtitle: "Elles détermineront les photos de suivi proposées. Plusieurs choix possibles.")
            VStack(spacing: GT.Spacing.s) {
                ForEach(ScalpZone.allCases) { zone in
                    ChoiceRow(title: zone.label, isSelected: model.draft.zones.contains(zone)) {
                        model.draft.zones.formSymmetricDifference([zone])
                    }
                }
            }
        }
    }
}

// MARK: - 6. Objectifs

struct GoalsStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: GT.Spacing.m) {
            StepHeader(title: "Tes objectifs",
                       subtitle: "Qu'attends-tu de Growtin' ? Ton programme mettra l'accent sur ces points.")
            VStack(spacing: GT.Spacing.s) {
                ForEach(PersonalGoal.allCases) { goal in
                    ChoiceRow(title: goal.label, systemImage: goal.symbol, isSelected: model.draft.goals.contains(goal)) {
                        model.draft.goals.formSymmetricDifference([goal])
                    }
                }
            }
        }
    }
}

// MARK: - 7. Sommeil et stress

struct SleepStressStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: GT.Spacing.m) {
            StepHeader(title: "Sommeil et stress",
                       subtitle: "Deux leviers importants pour ton bien-être général. Un stress intense peut aussi déclencher une chute temporaire.")

            FieldLabel(text: "Durée de sommeil habituelle")
            VStack(alignment: .trailing, spacing: GT.Spacing.xs) {
                Text(model.draft.sleepHours.formatted(.number.precision(.fractionLength(1))) + " h")
                    .font(.title3.weight(.semibold).monospacedDigit())
                Slider(value: $model.draft.sleepHours, in: 3...12, step: 0.5)
                    .accessibilityLabel("Durée de sommeil")
                    .accessibilityValue("\(model.draft.sleepHours.formatted()) heures")
            }

            FieldLabel(text: "Qualité du sommeil")
            Picker("Qualité du sommeil", selection: $model.draft.sleepQuality) {
                ForEach(SleepQuality.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            FieldLabel(text: "Niveau de stress ressenti ces dernières semaines")
            VStack(spacing: GT.Spacing.s) {
                ForEach(StressLevel.allCases) { level in
                    ChoiceRow(title: level.label, isSelected: model.draft.stress == level) { model.draft.stress = level }
                }
            }
        }
    }
}

// MARK: - 8. Alimentation et activité

struct NutritionActivityStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: GT.Spacing.m) {
            StepHeader(title: "Alimentation et activité",
                       subtitle: "Pour te proposer des conseils et, bientôt, des recettes compatibles avec tes habitudes.")

            FieldLabel(text: "Régime alimentaire")
            MultiChoiceChips(options: Array(DietPattern.allCases),
                             selection: Binding(get: { [model.draft.diet] }, set: { if let new = $0.subtracting([model.draft.diet]).first { model.draft.diet = new } }),
                             title: \.label)

            FieldLabel(text: "Rythme des repas")
            VStack(spacing: GT.Spacing.s) {
                ForEach(MealRegularity.allCases) { option in
                    ChoiceRow(title: option.label, isSelected: model.draft.mealRegularity == option) { model.draft.mealRegularity = option }
                }
            }

            FieldLabel(text: "Allergies ou aliments à éviter")
            MultiChoiceChips(options: Array(DietaryRestriction.allCases), selection: $model.draft.health.restrictions, title: \.label)

            FieldLabel(text: "Activité physique")
            VStack(spacing: GT.Spacing.s) {
                ForEach(ActivityLevel.allCases) { option in
                    ChoiceRow(title: option.label, isSelected: model.draft.activity == option) { model.draft.activity = option }
                }
            }
        }
    }
}

// MARK: - 9. Routine capillaire

struct HairCareStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: GT.Spacing.m) {
            StepHeader(title: "Ta routine capillaire",
                       subtitle: "Certaines habitudes de coiffage abîment la fibre ou exercent une tension sur les racines.")

            FieldLabel(text: "Fréquence des lavages")
            Picker("Fréquence des lavages", selection: $model.draft.washFrequency) {
                ForEach(WashFrequency.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu)
            .padding(.horizontal, GT.Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gtSurface, in: .rect(cornerRadius: GT.Radius.control))

            Toggle("Je porte souvent des coiffures serrées (queue-de-cheval, tresses, chignon, extensions)",
                   isOn: $model.draft.wearsTightHairstyles)
            Toggle("J'utilise régulièrement un lisseur, un fer ou un sèche-cheveux très chaud", isOn: $model.draft.usesHeatStyling)

            FieldLabel(text: "Produits utilisés actuellement")
            MultiChoiceChips(options: Array(HairProduct.allCases), selection: $model.draft.products, title: \.label, exclusive: HairProduct.none)
            if model.draft.products.contains(.other) {
                OtherDetailField(prompt: "Lesquels ? (ex. shampoing sec, lotion…)", text: $model.draft.otherProducts)
            }
        }
        .font(.body)
    }
}

// MARK: - 10. Santé (facultatif)

struct HealthStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: GT.Spacing.m) {
            StepHeader(eyebrow: "Facultatif",
                       title: "Ta santé",
                       subtitle: "Ces informations sensibles sont facultatives. Elles servent à adapter les contenus éducatifs et à t'orienter vers un médecin si nécessaire. Growtin' ne prescrit, ne dose et ne modifie jamais un traitement.")

            FieldLabel(text: "As-tu remarqué l'un de ces signes ?")
            MultiChoiceChips(options: Array(ReportedSymptom.allCases), selection: $model.draft.health.symptoms, title: \.label)
            if !model.draft.health.symptoms.isEmpty {
                Label("Ces signes justifient un avis médical. Nous te le rappellerons sur ton écran d'accueil.", systemImage: "stethoscope")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.gtAlert)
            }

            FieldLabel(text: "Diagnostic déjà posé par un médecin")
            Picker("Diagnostic", selection: $model.draft.health.diagnosis) {
                Text("Non renseigné").tag(KnownDiagnosis?.none)
                ForEach(KnownDiagnosis.allCases) { Text($0.label).tag(Optional($0)) }
            }
            .pickerStyle(.menu)

            FieldLabel(text: "Traitements suivis ou prescrits")
            MultiChoiceChips(options: Array(DeclaredTreatment.allCases), selection: $model.draft.health.treatments, title: \.label)

            FieldLabel(text: "Carences ou troubles identifiés par une prise de sang")
            MultiChoiceChips(options: Array(KnownDeficiency.allCases), selection: $model.draft.health.knownDeficiencies, title: \.label)

            if model.sex != .male {
                FieldLabel(text: "Grossesse et allaitement")
                Picker("Grossesse et allaitement", selection: $model.draft.health.pregnancy) {
                    Text("Non renseigné").tag(PregnancyStatus?.none)
                    ForEach(PregnancyStatus.allCases) { Text($0.label).tag(Optional($0)) }
                }
                .pickerStyle(.menu)
            }

            PrivacyNote(text: "Ces données restent sur ton iPhone et ne sont jamais revendues ni utilisées pour entraîner des modèles.")
        }
    }
}

// MARK: - 11. Préférences de suivi

struct TrackingStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: GT.Spacing.m) {
            StepHeader(title: "Ton suivi",
                       subtitle: "Les cheveux poussent lentement : des photos trop fréquentes montrent surtout des variations de lumière et de coiffage. Toutes les 4 semaines est un bon rythme.")
            VStack(spacing: GT.Spacing.s) {
                ForEach(PhotoFrequency.allCases) { frequency in
                    ChoiceRow(title: frequency.label, isSelected: model.draft.photoFrequency == frequency) {
                        model.draft.photoFrequency = frequency
                    }
                }
            }

            FieldLabel(text: "Assistant personnel")
            Toggle(isOn: $model.draft.consents.aiPersonalization) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Personnaliser l'assistant avec mon historique")
                        .font(.body.weight(.medium))
                    Text("Lorsque le Coach sera disponible, il pourra utiliser tes réponses et ton journal pour éviter les conseils génériques. Désactivable à tout moment.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - 12. Programme

struct SummaryStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        let routine = model.previewRoutine
        let alerts = model.previewAlerts
        VStack(alignment: .leading, spacing: GT.Spacing.m) {
            StepHeader(eyebrow: "Ton programme",
                       title: model.mode == .firstLaunch ? "Prêt à commencer" : "Tes réponses mises à jour",
                       subtitle: "Voici une première routine construite à partir de tes réponses. C'est un accompagnement éducatif et de bien-être, pas un traitement médical. Tu pourras tout ajuster.")

            ForEach(alerts) { SafetyBanner(alert: $0) }

            ForEach(DaySlot.allCases) { slot in
                let items = routine.filter { $0.slot == slot }
                if !items.isEmpty {
                    GTCard {
                        Label(slot.label, systemImage: slot.symbol).gtEyebrowStyle()
                        ForEach(items) { item in
                            VStack(alignment: .leading, spacing: GT.Spacing.xxs) {
                                Label(item.title, systemImage: item.symbol)
                                    .font(.body.weight(.semibold))
                                if let reason = item.reason {
                                    Text(reason)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, GT.Spacing.xxs)
                        }
                    }
                }
            }

            if case .edit = model.mode {
                Toggle("Mettre à jour les habitudes proposées par Growtin'", isOn: $model.regenerateRoutineOnSave)
                Text("Tes habitudes personnelles et ton historique sont conservés.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            FootnoteText(text: WellnessNotice.short)
        }
    }
}

/// Champ libre affiché quand « Autre » est sélectionné. Limité à 200 caractères.
struct OtherDetailField: View {
    let prompt: String
    @Binding var text: String?

    var body: some View {
        TextField(prompt, text: Binding(get: { text ?? "" }, set: { text = String($0.prefix(200)) }), axis: .vertical)
            .lineLimit(1...3)
            .textInputAutocapitalization(.sentences)
            .padding(GT.Spacing.s)
            .background(Color.gtSurface, in: .rect(cornerRadius: GT.Radius.control))
            .transition(.opacity.combined(with: .move(edge: .top)))
            .accessibilityLabel("Précision pour « Autre »")
    }
}
