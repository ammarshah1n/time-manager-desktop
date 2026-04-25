#if os(macOS)
// CalendarPane.swift — Timed macOS Preview
// Weekly calendar grid. Click a time block to see detail in a popover.
// Blocks are positioned by absolute hour offset within a ZStack.

import SwiftUI

private let kHourH:    CGFloat = 56   // px per hour
private let kTimeW:    CGFloat = 48   // time-label column width
private let kFirstH:   Int    = 6    // 6 am
private let kLastH:    Int    = 22   // 10 pm (exclusive)

struct CalendarPane: View {
    @Binding var blocks: [CalendarBlock]
    @StateObject private var auth = AuthService.shared
    @State private var weekOffset    = 0
    @State private var popoverBlock: CalendarBlock?
    @State private var focusBlock:   CalendarBlock?
    @State private var showBlockFocus = false
    @State private var editingBlock: CalendarBlock?
    @State private var isSyncing    = false
    @State private var freeTimeSlots: [FreeTimeSlot] = []
    @State private var syncedBlockIDs: Set<UUID> = []

    var weekDates: [Date] {
        let cal   = Calendar.current
        let today = cal.startOfDay(for: Date())
        let wd    = cal.component(.weekday, from: today)
        let mon   = cal.date(byAdding: .day, value: -(wd + 5) % 7 + weekOffset * 7, to: today)!
        return (0..<7).map { cal.date(byAdding: .day, value: $0, to: mon)! }
    }

    var todayIdx: Int? {
        weekDates.firstIndex { Calendar.current.isDateInToday($0) }
    }

    // Only blocks that fall in this week
    var visibleBlocks: [CalendarBlock] {
        let cal = Calendar.current
        return blocks.filter { block in
            weekDates.indices.contains(where: { cal.isDate(block.startTime, inSameDayAs: weekDates[$0]) })
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            CalendarHeaderRow(dates: weekDates, todayIdx: todayIdx)
            Divider()
            ScrollView(.vertical, showsIndicators: false) {
                CalendarGrid(
                    blocks: visibleBlocks,
                    dates: weekDates,
                    todayIdx: todayIdx,
                    freeTimeSlots: freeTimeSlots,
                    onTap: { popoverBlock = $0 },
                    onCreate: { block in
                        blocks.append(block)
                        editingBlock = block
                    }
                )
                .padding(.bottom, 32)
            }
        }
        .navigationTitle(weekTitle)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { withAnimation { weekOffset -= 1 } } label: {
                    Image(systemName: "chevron.left")
                }
            }
            ToolbarItem(placement: .navigation) {
                Button { withAnimation { weekOffset += 1 } } label: {
                    Image(systemName: "chevron.right")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { weekOffset = 0 } label: {
                    Text("Today").font(.system(size: 13, weight: .medium))
                }
                .disabled(weekOffset == 0)
            }
            ToolbarItem(placement: .primaryAction) {
                Button { syncCalendar() } label: {
                    HStack(spacing: 4) {
                        if isSyncing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        Text("Sync Calendar")
                            .font(.system(size: 13, weight: .medium))
                    }
                }
                .disabled(isSyncing)
            }
        }
        .popover(item: $popoverBlock) { block in
            BlockPopover(
                block: block,
                onStartFocus: {
                    popoverBlock = nil
                    focusBlock = block
                    showBlockFocus = true
                },
                onRemove: {
                    popoverBlock = nil
                    blocks.removeAll { $0.id == block.id }
                }
            )
            .frame(width: 300)
        }
        .sheet(isPresented: $showBlockFocus) {
            if let block = focusBlock {
                let durationMins = max(15, Int(block.endTime.timeIntervalSince(block.startTime) / 60))
                let fakeTask = TimedTask(
                    id: block.id,
                    title: block.title,
                    sender: block.category.rawValue.capitalized,
                    estimatedMinutes: durationMins,
                    bucket: .action,
                    emailCount: 0,
                    receivedAt: block.startTime
                )
                FocusPane(task: fakeTask) {
                    showBlockFocus = false
                    focusBlock = nil
                }
                .frame(minWidth: 600, minHeight: 680)
            }
        }
        .sheet(item: $editingBlock) { block in
            NewBlockEditor(block: block) { updated in
                if let idx = blocks.firstIndex(where: { $0.id == updated.id }) {
                    blocks[idx] = updated
                }
                editingBlock = nil
            } onCancel: {
                blocks.removeAll { $0.id == block.id }
                editingBlock = nil
            }
        }
    }

    var weekTitle: String {
        guard let first = weekDates.first, let last = weekDates.last else { return "" }
        let f = DateFormatter(); f.dateFormat = "MMM d"
        let cal = Calendar.current
        let sameMonth = cal.component(.month, from: first) == cal.component(.month, from: last)
        if sameMonth {
            let g = DateFormatter(); g.dateFormat = "d"
            return "\(f.string(from: first)) – \(g.string(from: last))"
        } else {
            return "\(f.string(from: first)) – \(f.string(from: last))"
        }
    }

    // MARK: - Calendar Sync

    private func syncCalendar() {
        guard !isSyncing else { return }

        // Retrieve token from environment / keychain. If unavailable, log and bail.
        guard auth.graphAccessToken != nil else {
            TimedLogger.calendar.warning("Sync Calendar: No Graph access token — skipping sync")
            return
        }

        let tokenProvider = auth.makeTokenProvider()
        isSyncing = true
        Task {
            defer { Task { @MainActor in isSyncing = false } }
            do {
                let service = CalendarSyncService.shared
                let fetched = try await service.fetchTodayEvents(tokenProvider: tokenProvider)

                // Remove previously synced blocks (so we don't duplicate on re-sync)
                await MainActor.run {
                    blocks.removeAll { syncedBlockIDs.contains($0.id) }
                    syncedBlockIDs.removeAll()
                }

                // Merge: add fetched blocks that don't overlap with user-created blocks
                let newIDs = Set(fetched.map(\.id))
                await MainActor.run {
                    blocks.append(contentsOf: fetched)
                    syncedBlockIDs = newIDs
                }

                // Detect free time from ALL blocks (user + synced)
                let allBlocks = await MainActor.run { blocks }
                let slots = await service.detectFreeTime(events: allBlocks)
                await MainActor.run {
                    freeTimeSlots = slots
                }

                TimedLogger.calendar.info("Calendar sync complete — \(fetched.count) events, \(slots.count) free slots")
            } catch {
                TimedLogger.calendar.error("Calendar sync failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

// MARK: - Header

struct CalendarHeaderRow: View {
    let dates: [Date]
    let todayIdx: Int?

    private let dayF = { let f = DateFormatter(); f.dateFormat = "EEE"; return f }()
    private let numF = { let f = DateFormatter(); f.dateFormat = "d";   return f }()

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: kTimeW)
            ForEach(Array(dates.enumerated()), id: \.offset) { idx, date in
                let isToday = idx == todayIdx
                VStack(spacing: 3) {
                    Text(dayF.string(from: date).uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isToday ? Color.Timed.accent : .secondary)
                    ZStack {
                        if isToday { Circle().fill(Color.Timed.accent).frame(width: 26, height: 26) }
                        Text(numF.string(from: date))
                            .font(.system(size: 15, weight: isToday ? .semibold : .regular))
                            .foregroundStyle(isToday ? .white : .primary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
            }
        }
    }
}

// MARK: - Grid

struct CalendarGrid: View {
    let blocks:   [CalendarBlock]
    let dates:    [Date]
    let todayIdx: Int?
    var freeTimeSlots: [FreeTimeSlot] = []
    let onTap:    (CalendarBlock) -> Void
    var onCreate: ((CalendarBlock) -> Void)? = nil

    // Drag-to-create state
    @State private var dragStartY: CGFloat?
    @State private var dragCurrentY: CGFloat?
    @State private var dragDayIndex: Int?

    private var totalHours: Int  { kLastH - kFirstH }
    private var gridHeight: CGFloat { CGFloat(totalHours + 1) * kHourH }

    private var nowOffset: CGFloat? {
        let cal = Calendar.current
        let now = Date()
        let h   = cal.component(.hour,   from: now)
        let m   = cal.component(.minute, from: now)
        guard h >= kFirstH, h < kLastH else { return nil }
        return CGFloat(Double(h - kFirstH) + Double(m) / 60.0) * kHourH
    }

    var body: some View {
        GeometryReader { geo in
            let colW = (geo.size.width - kTimeW) / CGFloat(dates.count)

            ZStack(alignment: .topLeading) {
                // Hour lines + labels
                VStack(spacing: 0) {
                    ForEach(kFirstH...kLastH, id: \.self) { hour in
                        HStack(alignment: .top, spacing: 0) {
                            Text(label(hour))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .frame(width: kTimeW - 8, alignment: .trailing)
                                .offset(y: -7)
                            Rectangle()
                                .fill(Color(.separatorColor).opacity(0.5))
                                .frame(height: 0.5)
                        }
                        .frame(height: kHourH)
                    }
                }

                // Half-hour ticks
                VStack(spacing: 0) {
                    ForEach(kFirstH..<kLastH, id: \.self) { _ in
                        VStack(spacing: 0) {
                            Color.clear.frame(height: kHourH / 2)
                            HStack(spacing: 0) {
                                Color.clear.frame(width: kTimeW)
                                Rectangle().fill(Color(.separatorColor).opacity(0.25)).frame(height: 0.5)
                            }
                            Color.clear.frame(height: kHourH / 2 - 0.5)
                        }
                    }
                }

                // Today column tint — monochrome surface wash, no accent flood.
                if let ti = todayIdx {
                    Rectangle()
                        .fill(Color.Timed.backgroundSecondary.opacity(0.6))
                        .frame(width: colW, height: CGFloat(totalHours) * kHourH)
                        .offset(x: kTimeW + colW * CGFloat(ti))
                }

                // Blocks
                ForEach(blocks) { block in
                    let dayIdx = blockDayIndex(block)
                    let yOff   = CGFloat(block.startHour - Double(kFirstH)) * kHourH
                    let bH     = max(CGFloat(block.durationHours) * kHourH - 2, 22)
                    let xOff   = kTimeW + colW * CGFloat(dayIdx) + 2

                    CalendarBlockCell(block: block)
                        .frame(width: colW - 4, height: bH)
                        .offset(x: xOff, y: yOff)
                        .onTapGesture { onTap(block) }
                }

                // Free time slots
                if let ti = todayIdx {
                    ForEach(freeTimeSlots) { slot in
                        let startHour = Double(Calendar.current.component(.hour, from: slot.start))
                            + Double(Calendar.current.component(.minute, from: slot.start)) / 60.0
                        let endHour = Double(Calendar.current.component(.hour, from: slot.end))
                            + Double(Calendar.current.component(.minute, from: slot.end)) / 60.0
                        let yOff = CGFloat(startHour - Double(kFirstH)) * kHourH
                        let slotH = max(CGFloat(endHour - startHour) * kHourH - 2, 22)
                        let xOff = kTimeW + colW * CGFloat(ti) + 2

                        FreeTimeSlotCell(slot: slot)
                            .frame(width: colW - 4, height: slotH)
                            .offset(x: xOff, y: yOff)
                    }
                }

                // Current-time line — Apple Calendar uses a red "now" indicator;
                // route it through our destructive token so it stays within the palette.
                if let yOff = nowOffset, let ti = todayIdx {
                    HStack(spacing: 0) {
                        Color.clear.frame(width: kTimeW + colW * CGFloat(ti) - 4)
                        Circle().fill(Color.Timed.destructive).frame(width: 8, height: 8)
                        Rectangle().fill(Color.Timed.destructive).frame(width: colW, height: 1.5)
                    }
                    .offset(y: yOff - 4)
                    .zIndex(10)
                }

                // Drag-to-create preview
                if let startY = dragStartY, let curY = dragCurrentY, let dayIdx = dragDayIndex {
                    let topY  = min(snappedY(startY), snappedY(curY))
                    let botY  = max(snappedY(startY), snappedY(curY))
                    let previewH = max(botY - topY, kHourH / 4)
                    let xOff  = kTimeW + colW * CGFloat(dayIdx) + 2

                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.Timed.accent.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                                    .foregroundStyle(Color.Timed.accent.opacity(0.5))
                            )
                        Text(dragTimeLabel(startY: startY, currentY: curY))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.Timed.accent)
                            .padding(.leading, 6).padding(.top, 4)
                    }
                    .frame(width: colW - 4, height: previewH)
                    .offset(x: xOff, y: topY)
                    .zIndex(20)
                }

                // Drag gesture overlay — covers the day columns
                Color.clear
                    .frame(width: geo.size.width - kTimeW, height: gridHeight)
                    .offset(x: kTimeW)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 4, coordinateSpace: .local)
                            .onChanged { value in
                                let x = value.startLocation.x - kTimeW
                                if dragDayIndex == nil {
                                    let idx = Int(x / colW)
                                    guard idx >= 0, idx < dates.count else { return }
                                    dragDayIndex = idx
                                }
                                if dragStartY == nil {
                                    dragStartY = clampY(value.startLocation.y)
                                }
                                dragCurrentY = clampY(value.location.y)
                            }
                            .onEnded { value in
                                defer { dragStartY = nil; dragCurrentY = nil; dragDayIndex = nil }

                                guard let startY = dragStartY, let dayIdx = dragDayIndex else { return }
                                let endY = clampY(value.location.y)

                                let topY = min(snappedY(startY), snappedY(endY))
                                let botY = max(snappedY(startY), snappedY(endY))

                                let startMin = yToMinutes(topY)
                                let endMin   = yToMinutes(botY)
                                guard endMin - startMin >= 15 else { return }

                                let cal  = Calendar.current
                                let day  = dates[dayIdx]
                                let sDate = cal.date(bySettingHour: (kFirstH * 60 + startMin) / 60,
                                                     minute: (kFirstH * 60 + startMin) % 60,
                                                     second: 0, of: day)!
                                let eDate = cal.date(bySettingHour: (kFirstH * 60 + endMin) / 60,
                                                     minute: (kFirstH * 60 + endMin) % 60,
                                                     second: 0, of: day)!

                                let block = CalendarBlock(
                                    id: UUID(),
                                    title: "New Block",
                                    startTime: sDate,
                                    endTime: eDate,
                                    sourceEmailId: nil,
                                    category: .focus
                                )
                                onCreate?(block)
                            }
                    )
            }
            .frame(width: geo.size.width, height: gridHeight)
        }
        .frame(height: gridHeight)
    }

    private func blockDayIndex(_ block: CalendarBlock) -> Int {
        let cal = Calendar.current
        return dates.firstIndex(where: { cal.isDate(block.startTime, inSameDayAs: $0) }) ?? block.weekdayIndex
    }

    private func label(_ h: Int) -> String {
        if h == 0  { return "12am" }
        if h == 12 { return "12pm" }
        return h < 12 ? "\(h)am" : "\(h - 12)pm"
    }

    // MARK: - Drag-to-create helpers

    /// Clamp Y to the grid bounds.
    private func clampY(_ y: CGFloat) -> CGFloat {
        min(max(y, 0), CGFloat(totalHours) * kHourH)
    }

    /// Snap Y to the nearest 15-minute increment.
    private func snappedY(_ y: CGFloat) -> CGFloat {
        let minutesPer15 = kHourH / 4 // 14pt per 15min at 56pt/hr
        return (y / minutesPer15).rounded() * minutesPer15
    }

    /// Convert a Y position to minutes from `kFirstH`.
    private func yToMinutes(_ y: CGFloat) -> Int {
        Int((y / kHourH) * 60)
    }

    /// Format a time label for the drag preview.
    private func dragTimeLabel(startY: CGFloat, currentY: CGFloat) -> String {
        let topY = min(snappedY(startY), snappedY(currentY))
        let botY = max(snappedY(startY), snappedY(currentY))
        let startMin = yToMinutes(topY) + kFirstH * 60
        let endMin   = yToMinutes(botY) + kFirstH * 60
        return "\(formatMinutes(startMin)) – \(formatMinutes(endMin))"
    }

    private func formatMinutes(_ totalMin: Int) -> String {
        let h = totalMin / 60
        let m = totalMin % 60
        let sfx = h >= 12 ? "PM" : "AM"
        let disp = h > 12 ? h - 12 : (h == 0 ? 12 : h)
        return m == 0 ? "\(disp) \(sfx)" : "\(disp):\(String(format: "%02d", m)) \(sfx)"
    }
}

// MARK: - Block Cell

struct CalendarBlockCell: View {
    let block: CalendarBlock

    var body: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(block.categoryColor.opacity(0.13))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(block.categoryColor).frame(width: 3)
            }
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(block.title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(block.categoryColor)
                        .lineLimit(2)
                    Text(block.startLabel)
                        .font(.system(size: 9))
                        .foregroundStyle(block.categoryColor.opacity(0.75))
                }
                .padding(.leading, 6).padding(.top, 4).padding(.trailing, 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

// MARK: - Block Popover

struct BlockPopover: View {
    let block: CalendarBlock
    let onStartFocus: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Accent header
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 3).fill(block.categoryColor).frame(width: 4, height: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(block.title).font(.headline)
                    Text(block.category.rawValue.capitalized)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Divider()

            // Time stats
            HStack(spacing: 20) {
                statCell("Start",    block.startLabel)
                statCell("End",      block.endLabel)
                statCell("Duration", block.durationLabel)
            }

            Divider()

            // Actions
            HStack {
                Button("Start Focus") { onStartFocus() }
                    .buttonStyle(.borderedProminent).tint(Color.Timed.accent).controlSize(.small)
                Spacer()
                Button("Remove", role: .destructive) { onRemove() }
                    .controlSize(.small)
            }
        }
        .padding(20)
    }

    @ViewBuilder
    func statCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary).textCase(.uppercase).tracking(0.5)
            Text(value)
                .font(.system(size: 14, weight: .medium))
        }
    }
}

// MARK: - Free Time Slot Cell

struct FreeTimeSlotCell: View {
    let slot: FreeTimeSlot

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.Timed.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        .foregroundStyle(Color.Timed.separator)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text("Free time")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.Timed.labelSecondary)
                Text("\(slot.durationMinutes) min")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.Timed.labelTertiary)
            }
            .padding(.leading, 6).padding(.top, 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

// MARK: - New Block Editor (post-create sheet)

struct NewBlockEditor: View {
    let block: CalendarBlock
    let onSave: (CalendarBlock) -> Void
    let onCancel: () -> Void

    @State private var title: String
    @State private var category: BlockCategory

    private static let categories: [BlockCategory] = [.focus, .meeting, .admin, .break]

    init(block: CalendarBlock, onSave: @escaping (CalendarBlock) -> Void, onCancel: @escaping () -> Void) {
        self.block = block
        self.onSave = onSave
        self.onCancel = onCancel
        self._title = State(initialValue: block.title)
        self._category = State(initialValue: block.category)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Block")
                .font(.headline)

            // Time display
            HStack(spacing: 16) {
                Label(block.startLabel, systemImage: "clock")
                Text("–")
                Text(block.endLabel)
                Spacer()
                Text(block.durationLabel)
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 13))

            Divider()

            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14))

            Picker("Category", selection: $category) {
                ForEach(Self.categories, id: \.self) { cat in
                    Text(cat.rawValue.capitalized).tag(cat)
                }
            }
            .pickerStyle(.segmented)

            Divider()

            HStack {
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    var updated = block
                    updated.title = title.isEmpty ? "New Block" : title
                    updated.category = category
                    onSave(updated)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}

#endif
