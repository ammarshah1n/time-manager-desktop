import AppKit
import Foundation
import PDFKit

struct PDFExportResult {
    let fileURL: URL
}

enum PDFExporterError: LocalizedError {
    case documentCreationFailed
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .documentCreationFailed:
            return "Timed could not build the PDF document."
        case .writeFailed:
            return "Timed could not save the PDF document."
        }
    }
}

enum PDFExporter {
    static let pageSize = CGSize(width: 595, height: 842)

    @MainActor
    static func exportDailyPlan(
        date: Date,
        tasks: [TaskItem],
        schedule: [ScheduleBlock],
        activePomodoroNote: String?,
        destinationURL: URL? = nil,
        openAfterSave: Bool = true,
        workspace: NSWorkspace = .shared,
        fileManager: FileManager = .default
    ) throws -> PDFExportResult {
        let exportURL = destinationURL ?? outputURL(for: date, fileManager: fileManager)
        let document = try makeDocument(
            date: date,
            tasks: Array(tasks.prefix(3)),
            schedule: schedule.sorted { $0.start < $1.start },
            activePomodoroNote: activePomodoroNote
        )

        try fileManager.createDirectory(
            at: exportURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        guard document.write(to: exportURL) else {
            throw PDFExporterError.writeFailed
        }

        if openAfterSave {
            openInPreview(exportURL, workspace: workspace)
        }

        return PDFExportResult(fileURL: exportURL)
    }

    @MainActor
    static func makeDocument(
        date: Date,
        tasks: [TaskItem],
        schedule: [ScheduleBlock],
        activePomodoroNote: String?
    ) throws -> PDFDocument {
        let view = DailyPlanPDFView(
            frame: CGRect(origin: .zero, size: pageSize),
            date: date,
            tasks: Array(tasks.prefix(3)),
            schedule: schedule.sorted { $0.start < $1.start },
            activePomodoroNote: activePomodoroNote?.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        let data = view.dataWithPDF(inside: view.bounds)
        guard let document = PDFDocument(data: data) else {
            throw PDFExporterError.documentCreationFailed
        }

        return document
    }

    static func outputURL(for date: Date, fileManager: FileManager = .default) -> URL {
        let downloadsDirectory = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let fileName = "Timed-\(fileDateFormatter.string(from: date)).pdf"
        return downloadsDirectory.appendingPathComponent(fileName)
    }

    private static func openInPreview(_ url: URL, workspace: NSWorkspace) {
        if let previewURL = workspace.urlForApplication(withBundleIdentifier: "com.apple.Preview") {
            let configuration = NSWorkspace.OpenConfiguration()
            workspace.open([url], withApplicationAt: previewURL, configuration: configuration) { _, _ in }
            return
        }

        workspace.open(url)
    }

    private static var fileDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private static var headerDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter
    }

    private static var deadlineFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "EEE d MMM"
        return formatter
    }

    private static var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }

    private final class DailyPlanPDFView: NSView {
        private let exportDate: Date
        private let tasks: [TaskItem]
        private let schedule: [ScheduleBlock]
        private let activePomodoroNote: String?

        override var isFlipped: Bool { true }

        init(
            frame: CGRect,
            date: Date,
            tasks: [TaskItem],
            schedule: [ScheduleBlock],
            activePomodoroNote: String?
        ) {
            self.exportDate = date
            self.tasks = tasks
            self.schedule = schedule
            self.activePomodoroNote = activePomodoroNote?.nilIfBlank
            super.init(frame: frame)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func draw(_ dirtyRect: NSRect) {
            NSColor.white.setFill()
            dirtyRect.fill()

            let margin: CGFloat = 46
            let contentWidth = bounds.width - (margin * 2)
            let sectionSpacing: CGFloat = 28
            var y = margin

            y = drawHeader(at: CGPoint(x: margin, y: y), width: contentWidth)
            y += sectionSpacing
            y = drawTasksSection(at: CGPoint(x: margin, y: y), width: contentWidth)
            y += sectionSpacing
            _ = drawScheduleSection(at: CGPoint(x: margin, y: y), width: contentWidth)
        }

        private func drawHeader(at origin: CGPoint, width: CGFloat) -> CGFloat {
            let titleAttributes = textAttributes(fontSize: 28, weight: .bold)
            let subtitleAttributes = textAttributes(fontSize: 13, weight: .medium, color: .secondaryLabelColor)
            let accentAttributes = textAttributes(fontSize: 11, weight: .semibold, color: .secondaryLabelColor)

            let title = "Timed Daily Plan"
            let subtitle = PDFExporter.headerDateFormatter.string(from: exportDate)
            let accent = "Generated for today’s ranked tasks and approved study blocks"

            let titleHeight = title.drawHeight(width: width, attributes: titleAttributes)
            title.draw(in: CGRect(x: origin.x, y: origin.y, width: width, height: titleHeight), withAttributes: titleAttributes)

            let subtitleY = origin.y + titleHeight + 6
            let subtitleHeight = subtitle.drawHeight(width: width, attributes: subtitleAttributes)
            subtitle.draw(in: CGRect(x: origin.x, y: subtitleY, width: width, height: subtitleHeight), withAttributes: subtitleAttributes)

            let accentY = subtitleY + subtitleHeight + 10
            accent.draw(in: CGRect(x: origin.x, y: accentY, width: width, height: 18), withAttributes: accentAttributes)

            let lineY = accentY + 24
            let line = NSBezierPath()
            line.move(to: CGPoint(x: origin.x, y: lineY))
            line.line(to: CGPoint(x: origin.x + width, y: lineY))
            NSColor(calibratedWhite: 0.86, alpha: 1).setStroke()
            line.lineWidth = 1
            line.stroke()

            return lineY
        }

        private func drawTasksSection(at origin: CGPoint, width: CGFloat) -> CGFloat {
            let sectionTitleAttributes = textAttributes(fontSize: 16, weight: .bold)
            let titleAttributes = textAttributes(fontSize: 13, weight: .semibold)
            let metaAttributes = textAttributes(fontSize: 11, weight: .medium, color: .secondaryLabelColor)
            let bodyAttributes = textAttributes(fontSize: 11, weight: .regular)

            let sectionTitle = "Top 3 Tasks"
            sectionTitle.draw(at: origin, withAttributes: sectionTitleAttributes)

            var y = origin.y + 28
            if tasks.isEmpty {
                let emptyState = "No ranked tasks are loaded right now."
                emptyState.draw(
                    in: CGRect(x: origin.x, y: y, width: width, height: 20),
                    withAttributes: bodyAttributes
                )
                return y + 24
            }

            for (index, task) in tasks.enumerated() {
                let numberRect = CGRect(x: origin.x, y: y + 2, width: 22, height: 22)
                let numberPath = NSBezierPath(roundedRect: numberRect, xRadius: 6, yRadius: 6)
                NSColor(calibratedRed: 0.90, green: 0.93, blue: 1.0, alpha: 1).setFill()
                numberPath.fill()

                let number = "\(index + 1)"
                let numberAttributes = textAttributes(fontSize: 11, weight: .bold, color: .black)
                let numberSize = number.size(withAttributes: numberAttributes)
                number.draw(
                    at: CGPoint(
                        x: numberRect.midX - (numberSize.width / 2),
                        y: numberRect.midY - (numberSize.height / 2)
                    ),
                    withAttributes: numberAttributes
                )

                let textX = origin.x + 34
                let titleHeight = task.title.drawHeight(width: width - 34, attributes: titleAttributes)
                task.title.draw(
                    in: CGRect(x: textX, y: y, width: width - 34, height: titleHeight),
                    withAttributes: titleAttributes
                )

                let deadlineText: String
                if let dueDate = task.dueDate {
                    deadlineText = "Deadline: \(PDFExporter.deadlineFormatter.string(from: dueDate))"
                } else {
                    deadlineText = "Deadline: None"
                }

                let metadata = "\(task.subject) • \(deadlineText) • Importance \(task.importance)"
                let metaY = y + titleHeight + 4
                let metaHeight = metadata.drawHeight(width: width - 34, attributes: metaAttributes)
                metadata.draw(
                    in: CGRect(x: textX, y: metaY, width: width - 34, height: metaHeight),
                    withAttributes: metaAttributes
                )

                if let notes = task.notes.nilIfBlank {
                    let noteY = metaY + metaHeight + 4
                    let noteHeight = notes.drawHeight(width: width - 34, attributes: bodyAttributes)
                    notes.draw(
                        in: CGRect(x: textX, y: noteY, width: width - 34, height: noteHeight),
                        withAttributes: bodyAttributes
                    )
                    y = noteY + noteHeight + 18
                } else {
                    y = metaY + metaHeight + 18
                }
            }

            return y
        }

        private func drawScheduleSection(at origin: CGPoint, width: CGFloat) -> CGFloat {
            let sectionTitleAttributes = textAttributes(fontSize: 16, weight: .bold)
            let labelAttributes = textAttributes(fontSize: 12, weight: .semibold)
            let detailAttributes = textAttributes(fontSize: 11, weight: .regular, color: .secondaryLabelColor)
            let bodyAttributes = textAttributes(fontSize: 11, weight: .regular)

            let sectionTitle = "Schedule"
            sectionTitle.draw(at: origin, withAttributes: sectionTitleAttributes)

            var y = origin.y + 30
            if let activePomodoroNote {
                let noteRect = CGRect(x: origin.x, y: y, width: width, height: 40)
                let notePath = NSBezierPath(roundedRect: noteRect, xRadius: 12, yRadius: 12)
                NSColor(calibratedRed: 0.97, green: 0.96, blue: 0.88, alpha: 1).setFill()
                notePath.fill()

                let noteTitle = "Active Pomodoro"
                noteTitle.draw(
                    at: CGPoint(x: noteRect.minX + 12, y: noteRect.minY + 8),
                    withAttributes: textAttributes(fontSize: 11, weight: .bold)
                )
                activePomodoroNote.draw(
                    in: CGRect(x: noteRect.minX + 12, y: noteRect.minY + 20, width: noteRect.width - 24, height: 14),
                    withAttributes: detailAttributes
                )
                y += 54
            }

            if schedule.isEmpty {
                let emptyState = "No schedule blocks for today."
                emptyState.draw(
                    in: CGRect(x: origin.x, y: y, width: width, height: 20),
                    withAttributes: bodyAttributes
                )
                return y + 24
            }

            let timelineX = origin.x + 64
            let cardX = origin.x + 92
            let cardWidth = width - (cardX - origin.x)
            let rowHeight: CGFloat = 64
            let lineStartY = y + 10
            let lineEndY = y + (CGFloat(schedule.count) * rowHeight) - 14

            let timelineLine = NSBezierPath()
            timelineLine.move(to: CGPoint(x: timelineX, y: lineStartY))
            timelineLine.line(to: CGPoint(x: timelineX, y: lineEndY))
            NSColor(calibratedWhite: 0.83, alpha: 1).setStroke()
            timelineLine.lineWidth = 2
            timelineLine.stroke()

            for (index, block) in schedule.enumerated() {
                let rowY = y + (CGFloat(index) * rowHeight)
                let timeText = "\(PDFExporter.timeFormatter.string(from: block.start)) – \(PDFExporter.timeFormatter.string(from: block.end))"
                timeText.draw(
                    in: CGRect(x: origin.x, y: rowY + 10, width: 56, height: 18),
                    withAttributes: detailAttributes
                )

                let dotRect = CGRect(x: timelineX - 5, y: rowY + 16, width: 10, height: 10)
                let dotPath = NSBezierPath(ovalIn: dotRect)
                NSColor(calibratedRed: 0.28, green: 0.46, blue: 0.88, alpha: 1).setFill()
                dotPath.fill()

                let cardRect = CGRect(x: cardX, y: rowY, width: cardWidth, height: 48)
                let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: 12, yRadius: 12)
                NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
                cardPath.fill()

                let title = block.title
                title.draw(
                    in: CGRect(x: cardRect.minX + 12, y: cardRect.minY + 8, width: cardRect.width - 24, height: 16),
                    withAttributes: labelAttributes
                )

                let detail = block.note.nilIfBlank ?? block.timeRange
                detail.draw(
                    in: CGRect(x: cardRect.minX + 12, y: cardRect.minY + 24, width: cardRect.width - 24, height: 16),
                    withAttributes: detailAttributes
                )
            }

            return y + (CGFloat(schedule.count) * rowHeight)
        }

        private func textAttributes(
            fontSize: CGFloat,
            weight: NSFont.Weight,
            color: NSColor = .black
        ) -> [NSAttributedString.Key: Any] {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineBreakMode = .byWordWrapping
            paragraphStyle.lineSpacing = 1.4

            return [
                .font: NSFont.systemFont(ofSize: fontSize, weight: weight),
                .foregroundColor: color,
                .paragraphStyle: paragraphStyle
            ]
        }
    }
}

private extension String {
    func drawHeight(width: CGFloat, attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        let rect = (self as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        return ceil(rect.height)
    }

    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
