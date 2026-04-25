import SwiftUI

struct ConversationView: View {
    @Binding private var tasks: [TimedTask]
    @Binding private var blocks: [CalendarBlock]
    @StateObject private var model: ConversationModel
    @Environment(\.dismiss) private var dismiss
    @State private var transcriptCollapsed = true

    init(tasks: Binding<[TimedTask]>, blocks: Binding<[CalendarBlock]>, freeTimeSlots: [FreeTimeSlot]) {
        _tasks = tasks
        _blocks = blocks
        _model = StateObject(wrappedValue: ConversationModel(tasks: tasks, blocks: blocks, freeTimeSlots: freeTimeSlots))
    }

    var body: some View {
        ZStack {
            Color.Timed.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: TimedLayout.Spacing.xl) {
                Spacer(minLength: TimedLayout.Spacing.xxl)

                OrbView(isActive: model.isSpeaking, phase: orbPhase)
                    .frame(width: 220, height: 220)

                Text(model.phaseTitle)
                    .font(TimedType.title)
                    .foregroundStyle(phaseColor)

                MicActivityBar(isListening: model.isListening)
                    .frame(width: 72, height: 30)

                transcriptSection
                    .frame(maxWidth: 620)

                Spacer()

                HStack {
                    Spacer()
                    Button("Done") {
                        Task {
                            await model.end()
                            dismiss()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(Color.Timed.accent)
                    .keyboardShortcut(.return, modifiers: [])
                }
                .padding(.horizontal, TimedLayout.Spacing.xl)
                .padding(.bottom, TimedLayout.Spacing.xl)
            }
        }
        .task { await model.start() }
        .onDisappear {
            Task { await model.end() }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var phaseColor: Color {
        if case .failed = model.phase {
            return Color.Timed.destructive
        }
        return model.isListening || model.isSpeaking ? Color.Timed.labelPrimary : Color.Timed.labelSecondary
    }

    private var orbPhase: MorningCheckInManager.Phase {
        switch model.phase {
        case .idle: .idle
        case .connecting, .thinking: .connecting
        case .listening, .speaking: .active
        case .ending: .ending
        case .ended: .ended
        case .failed(let message): .failed(message)
        }
    }

    private var transcriptSection: some View {
        VStack(spacing: TimedLayout.Spacing.xs) {
            Button {
                withAnimation(TimedMotion.smooth) { transcriptCollapsed.toggle() }
            } label: {
                HStack(spacing: TimedLayout.Spacing.xxs) {
                    Image(systemName: transcriptCollapsed ? "chevron.down" : "chevron.up")
                        .font(TimedType.caption2)
                    Text(transcriptCollapsed ? "Show transcript" : "Hide transcript")
                        .font(TimedType.footnote)
                }
                .foregroundStyle(Color.Timed.labelSecondary)
            }
            .buttonStyle(.plain)

            if !transcriptCollapsed {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: TimedLayout.Spacing.xs) {
                            ForEach(model.transcript) { message in
                                HStack(alignment: .top, spacing: TimedLayout.Spacing.sm) {
                                    Text(message.role)
                                        .font(TimedType.caption2)
                                        .foregroundStyle(Color.Timed.labelTertiary)
                                        .frame(width: 44, alignment: .leading)
                                    Text(message.content)
                                        .font(TimedType.footnote)
                                        .foregroundStyle(Color.Timed.labelSecondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .id(message.id)
                            }
                            if !model.liveTranscript.isEmpty {
                                HStack(alignment: .top, spacing: TimedLayout.Spacing.sm) {
                                    Text("You")
                                        .font(TimedType.caption2)
                                        .foregroundStyle(Color.Timed.labelTertiary)
                                        .frame(width: 44, alignment: .leading)
                                    Text(model.liveTranscript)
                                        .font(TimedType.footnote)
                                        .foregroundStyle(Color.Timed.labelTertiary)
                                }
                            }
                        }
                        .padding(.horizontal, TimedLayout.Spacing.xl)
                        .padding(.vertical, TimedLayout.Spacing.sm)
                    }
                    .frame(maxHeight: 220)
                    .onChange(of: model.transcript.count) { _, _ in
                        if let last = model.transcript.last {
                            withAnimation(TimedMotion.smooth) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
