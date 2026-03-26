import SwiftUI

struct ConfidenceCalibrationDraft: Hashable {
    let subject: String
    var confidence = 3.0
    var recentTopic = ""
    var leastSureAbout = ""
    var assessmentDate = ""
    var resources = ""
}

struct ConfidenceCalibrationResponse: Decodable {
    let confidence: Int
    let hints: [String]
}

struct ConfidenceCalibrationBanner: View {
    let subject: String
    let onAccept: () -> Void
    let onSkip: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "bolt.badge.questionmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))

            Text("New subject: \(subject). Run a quick confidence check?")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))

            Spacer(minLength: 12)

            Button("Yes, 2 min", action: onAccept)
                .buttonStyle(.borderedProminent)

            Button("Skip", action: onSkip)
                .buttonStyle(.bordered)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
    }
}

struct ConfidenceCalibrationView: View {
    let subject: String
    let suggestedAssessmentDate: String
    let onSubmit: @MainActor (ConfidenceCalibrationDraft) async -> String?
    let onCancel: () -> Void
    let onComplete: () -> Void

    @State private var draft: ConfidenceCalibrationDraft
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    init(
        subject: String,
        suggestedAssessmentDate: String,
        onSubmit: @escaping @MainActor (ConfidenceCalibrationDraft) async -> String?,
        onCancel: @escaping () -> Void,
        onComplete: @escaping () -> Void
    ) {
        self.subject = subject
        self.suggestedAssessmentDate = suggestedAssessmentDate
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        self.onComplete = onComplete
        _draft = State(
            initialValue: ConfidenceCalibrationDraft(
                subject: subject,
                confidence: 3,
                assessmentDate: suggestedAssessmentDate
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Confidence check for \(subject)")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)

            questionBlock("How confident are you in this topic? (1-5)") {
                Picker("Confidence", selection: $draft.confidence) {
                    ForEach(1...5, id: \.self) { value in
                        Text("\(value)").tag(Double(value))
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            questionBlock("What's the most recent thing you covered?") {
                TextField("Eg. market failure graphs", text: $draft.recentTopic)
                    .textFieldStyle(.roundedBorder)
            }

            questionBlock("What are you least sure about?") {
                TextField("Eg. PED vs PES", text: $draft.leastSureAbout)
                    .textFieldStyle(.roundedBorder)
            }

            questionBlock("When is the assessment?") {
                TextField("Eg. Friday or 2 April", text: $draft.assessmentDate)
                    .textFieldStyle(.roundedBorder)
            }

            questionBlock("What resources do you have?") {
                TextField("Workbook, class notes, teacher slides", text: $draft.resources)
                    .textFieldStyle(.roundedBorder)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.red.opacity(0.9))
            }

            HStack(spacing: 10) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)

                Button(isSubmitting ? "Checking..." : "Apply") {
                    Task { await submit() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSubmitting || !isDraftReady)

                if isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .padding(18)
        .frame(width: 420)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
        )
    }

    private var isDraftReady: Bool {
        !draft.recentTopic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !draft.leastSureAbout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !draft.assessmentDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !draft.resources.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private func questionBlock<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
            content()
        }
    }

    @MainActor
    private func submit() async {
        errorMessage = nil
        isSubmitting = true
        let result = await onSubmit(draft)
        isSubmitting = false

        if let result {
            errorMessage = result
            return
        }

        onComplete()
    }
}
