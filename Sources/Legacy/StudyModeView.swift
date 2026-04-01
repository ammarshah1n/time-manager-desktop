import AppKit
import Charts
import SwiftUI

struct StudyModeView: View {
    let store: PlannerStore
    @Binding var selectedSubject: String
    let onStartQuiz: (String) -> Void

    @State private var searchText = ""

    private var subjects: [String] {
        store.studyModeSubjects()
    }

    private var activeSubject: String {
        if subjects.contains(where: { $0.caseInsensitiveCompare(selectedSubject) == .orderedSame }) {
            return selectedSubject
        }
        return subjects.first ?? ""
    }

    private var confidencePercent: Int {
        store.subjectConfidencePercent(for: activeSubject)
    }

    private var dueQuizCount: Int {
        guard !activeSubject.isEmpty else { return 0 }
        return store.dueQuizCardCount(for: activeSubject)
    }

    private var confidenceTrendReadings: [ConfidenceReading] {
        guard !activeSubject.isEmpty else { return [] }
        return store.lastConfidenceReadings(for: activeSubject, limit: 7)
    }

    private var topNotes: [ContextDocument] {
        guard !activeSubject.isEmpty else { return [] }
        let documents = store.topDocuments(for: activeSubject, limit: 3)
        guard !searchText.isEmpty else { return documents }

        let normalizedSearch = searchText.lowercased()
        return documents.filter { document in
            let haystack = "\(document.title) \(document.path) \(document.content)".lowercased()
            return haystack.contains(normalizedSearch)
        }
    }

    private var transcriptContexts: [ContextItem] {
        store.transcriptStudyContexts(for: activeSubject, searchText: searchText, limit: 6)
    }

    private var preferredTaskAvailable: Bool {
        store.tasks.contains {
            !$0.isCompleted && $0.subject.caseInsensitiveCompare(activeSubject) == .orderedSame
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            studySubjectList
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 320, maxHeight: .infinity)

            studySurface
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            ensureSelectedSubject()
        }
        .onChange(of: subjects) { _, _ in
            ensureSelectedSubject()
        }
    }

    private var studySubjectList: some View {
        ZStack {
            TimedVisualEffectBackground(material: .sidebar, blendingMode: .withinWindow)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.06),
                    Color.clear,
                    Color.black.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    TimedSectionHeader(title: "Subjects")

                    if subjects.isEmpty {
                        Text("No subjects loaded yet.")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.58))
                            .padding(.horizontal, 18)
                            .padding(.bottom, 18)
                    } else {
                        ForEach(subjects, id: \.self) { subject in
                            SubjectStudyRow(
                                subject: subject,
                                confidencePercent: store.subjectConfidencePercent(for: subject),
                                latestGrade: store.latestGrade(for: subject),
                                recentGrades: store.recentGrades(for: subject, limit: 3),
                                dueQuizCount: store.dueQuizCardCount(for: subject),
                                isSelected: subject.caseInsensitiveCompare(activeSubject) == .orderedSame,
                                action: {
                                    selectedSubject = subject
                                }
                            )
                            .padding(.horizontal, 12)
                        }
                        .padding(.bottom, 12)
                    }
                }
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: 14)
    }

    private var studySurface: some View {
        ZStack {
            TimedVisualEffectBackground(material: .fullScreenUI, blendingMode: .withinWindow)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.04),
                    Color.clear,
                    Color.black.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TimedCard(title: "Study surface", icon: "book.pages") {
                        VStack(alignment: .leading, spacing: 14) {
                            if activeSubject.isEmpty {
                                Text("Choose a subject to begin.")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.58))
                            } else {
                                HStack(alignment: .top, spacing: 16) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(activeSubject)
                                            .font(.custom("Fraunces", size: 32))
                                            .fontWeight(.bold)
                                            .foregroundStyle(.white)

                                        Text("Confidence \(confidencePercent)%")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(.white.opacity(0.64))
                                    }

                                    Spacer()

                                    Button("Start Quiz") {
                                        onStartQuiz(activeSubject)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(!preferredTaskAvailable)

                                    dueQuizBadge(count: dueQuizCount)
                                }

                                ProgressView(value: Double(confidencePercent), total: 100)
                                    .progressViewStyle(.linear)
                                    .tint(confidenceTint(for: confidencePercent))

                                TextField("Search notes and excerpts", text: $searchText)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 14))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .background(searchFieldBackground)

                                if !preferredTaskAvailable {
                                    Text("Quiz requires at least one active task for this subject.")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.54))
                                }

                                confidenceTrendPanel
                            }
                        }
                    }

                    StudySurfaceSection(title: "Top Obsidian notes", icon: "books.vertical") {
                        if topNotes.isEmpty {
                            emptyStateText(
                                searchText.isEmpty
                                    ? "No Obsidian notes matched this subject."
                                    : "No Obsidian notes matched your search."
                            )
                        } else {
                            ForEach(topNotes) { document in
                                StudyNoteCard(document: document, searchText: searchText)
                            }
                        }
                    }

                    StudySurfaceSection(title: "Transcript excerpts", icon: "text.book.closed") {
                        if transcriptContexts.isEmpty {
                            emptyStateText(
                                searchText.isEmpty
                                    ? "No transcript excerpts matched this subject."
                                    : "No transcript excerpts matched your search."
                            )
                        } else {
                            ForEach(transcriptContexts) { context in
                                StudyExcerptCard(context: context, searchText: searchText)
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .padding(18)
            .scrollIndicators(.hidden)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 28, x: 0, y: 16)
    }

    private var searchFieldBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.18))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }

    @ViewBuilder
    private func emptyStateText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.58))
    }

    @ViewBuilder
    private var confidenceTrendPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Confidence trend")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))

                Spacer()

                Text("Last 7 readings")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.52))
            }

            if confidenceTrendReadings.count < 2 {
                Text("Complete calibration to see trend")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.58))
                    .frame(maxWidth: .infinity, minHeight: 170, alignment: .leading)
            } else {
                Chart(confidenceTrendReadings) { reading in
                    LineMark(
                        x: .value("Date", reading.date),
                        y: .value("Score", reading.value * 100)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color(red: 0.82, green: 0.94, blue: 1.0))

                    PointMark(
                        x: .value("Date", reading.date),
                        y: .value("Score", reading.value * 100)
                    )
                    .foregroundStyle(Color.white)
                }
                .chartXAxis {
                    AxisMarks(values: confidenceTrendReadings.map(\.date)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.white.opacity(0.10))
                        AxisTick()
                            .foregroundStyle(Color.white.opacity(0.24))
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                            .foregroundStyle(Color.white.opacity(0.58))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.white.opacity(0.10))
                        AxisTick()
                            .foregroundStyle(Color.white.opacity(0.24))
                        AxisValueLabel {
                            if let score = value.as(Double.self) {
                                Text("\(Int(score))")
                            }
                        }
                        .foregroundStyle(Color.white.opacity(0.58))
                    }
                }
                .chartYScale(domain: 0...100)
                .frame(height: 170)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func ensureSelectedSubject() {
        if !activeSubject.isEmpty && selectedSubject.caseInsensitiveCompare(activeSubject) != .orderedSame {
            selectedSubject = activeSubject
        }
    }

    private func confidenceTint(for percent: Int) -> Color {
        switch percent {
        case ..<40:
            return .red
        case 40..<70:
            return .orange
        default:
            return .green
        }
    }

    private func dueQuizBadge(count: Int) -> some View {
        Text("\(count) due")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.82))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
    }
}

private struct SubjectStudyRow: View {
    let subject: String
    let confidencePercent: Int
    let latestGrade: GradeEntry?
    let recentGrades: [GradeEntry]
    let dueQuizCount: Int
    let isSelected: Bool
    let action: () -> Void

    @State private var isShowingGradePopover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(subject)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.88))
                    Spacer()
                    Text("\(dueQuizCount) due")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                        )
                    Text("\(confidencePercent)%")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.58))
                }

                HStack(spacing: 10) {
                    ProgressView(value: Double(confidencePercent), total: 100)
                        .progressViewStyle(.linear)
                        .tint(progressTint)

                    if let latestGrade {
                        GradeBadge(
                            latestGrade: latestGrade,
                            recentGrades: recentGrades,
                            isShowingPopover: $isShowingGradePopover
                        )
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.10) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.16) : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var progressTint: Color {
        switch confidencePercent {
        case ..<40:
            return .red
        case 40..<70:
            return .orange
        default:
            return .green
        }
    }
}

private struct GradeBadge: View {
    let latestGrade: GradeEntry
    let recentGrades: [GradeEntry]
    @Binding var isShowingPopover: Bool

    var body: some View {
        HStack(spacing: 5) {
            Text("\(latestGrade.mark)/\(latestGrade.outOf)")
                .font(.system(size: 11, weight: .semibold))

            if let trendSymbol {
                Image(systemName: trendSymbol)
                    .font(.system(size: 9, weight: .bold))
            }
        }
        .foregroundStyle(.white.opacity(0.82))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.10))
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .onHover { isHovering in
            guard !recentGrades.isEmpty else { return }
            isShowingPopover = isHovering
        }
        .popover(isPresented: $isShowingPopover, arrowEdge: .top) {
            GradePopoverContent(recentGrades: recentGrades)
        }
    }

    private var trendSymbol: String? {
        guard recentGrades.count >= 2 else { return nil }
        let latestScore = Double(recentGrades[0].mark) / Double(max(1, recentGrades[0].outOf))
        let previousScore = Double(recentGrades[1].mark) / Double(max(1, recentGrades[1].outOf))

        if latestScore > previousScore {
            return "arrow.up.right"
        }
        if latestScore < previousScore {
            return "arrow.down.right"
        }
        return "minus"
    }
}

private struct GradePopoverContent: View {
    let recentGrades: [GradeEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent assessments")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            ForEach(recentGrades) { grade in
                VStack(alignment: .leading, spacing: 4) {
                    Text(grade.assessmentTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        Text("\(grade.mark)/\(grade.outOf)")
                            .font(.system(size: 12, weight: .medium))
                        Text(grade.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(width: 260, alignment: .leading)
    }
}

private struct StudySurfaceSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        TimedCard(title: title, icon: icon) {
            VStack(alignment: .leading, spacing: 12) {
                content
            }
        }
    }
}

private struct StudyNoteCard: View {
    let document: ContextDocument
    let searchText: String

    var body: some View {
        TimedCard(title: document.title, icon: "doc.richtext") {
            VStack(alignment: .leading, spacing: 10) {
                Text(document.path)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.48))
                    .textSelection(.enabled)

                Text(snippet(from: document.content))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.78))
                    .textSelection(.enabled)
            }
        }
    }

    private func snippet(from content: String) -> String {
        excerpt(from: content, matching: searchText, fallbackLimit: 320)
    }
}

private struct StudyExcerptCard: View {
    let context: ContextItem
    let searchText: String

    var body: some View {
        TimedCard(title: context.title, icon: "waveform.and.mic") {
            VStack(alignment: .leading, spacing: 10) {
                Text(context.kind)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.48))

                Text(snippet)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.78))
                    .textSelection(.enabled)
            }
        }
    }

    private var snippet: String {
        let sourceText = context.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? context.summary
            : context.detail
        return excerpt(from: sourceText, matching: searchText, fallbackLimit: 340)
    }
}

private func excerpt(from text: String, matching searchText: String, fallbackLimit: Int) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "No content available." }

    let normalizedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedSearch.isEmpty else {
        return String(trimmed.prefix(fallbackLimit))
    }

    let loweredText = trimmed.lowercased()
    let loweredSearch = normalizedSearch.lowercased()

    guard let matchRange = loweredText.range(of: loweredSearch) else {
        return String(trimmed.prefix(fallbackLimit))
    }

    let startOffset = loweredText.distance(from: loweredText.startIndex, to: matchRange.lowerBound)
    let lowerBound = max(0, startOffset - 80)
    let upperBound = min(trimmed.count, startOffset + normalizedSearch.count + 180)
    let startIndex = trimmed.index(trimmed.startIndex, offsetBy: lowerBound)
    let endIndex = trimmed.index(trimmed.startIndex, offsetBy: upperBound)
    let excerpt = String(trimmed[startIndex..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)

    let prefix = lowerBound > 0 ? "..." : ""
    let suffix = upperBound < trimmed.count ? "..." : ""
    return prefix + excerpt + suffix
}
