import AppKit
import SwiftUI
@preconcurrency import Translation

@MainActor
struct SelectionOverlayView: View {
    static let expandedWidth: CGFloat = 324

    @ObservedObject var store: SelectionOverlayStore
    let onToggleMore: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            actionBar

            if let recommendation = store.recommendation,
               !store.isMorePresented,
               isCompactPhase {
                Divider().opacity(0.55)
                recommendationRow(recommendation)
            }

            phaseContent

            if store.isMorePresented {
                Divider().opacity(0.55)
                moreCapabilities
            }
        }
        .frame(width: Self.expandedWidth)
        .background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(overlaySurface)
                .shadow(color: overlayShadow, radius: 12, y: 5)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(overlayBorder, lineWidth: 0.75)
        }
        .onExitCommand {
            if store.isMorePresented {
                store.hideMore()
            } else {
                store.dismiss()
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 0) {
            actionButton(
                title: "复制",
                symbolName: "doc.on.doc",
                isLoading: false,
                action: store.copySelection
            )

            actionButton(
                title: "粘贴",
                symbolName: "doc.on.clipboard",
                isLoading: false,
                action: store.pasteClipboard
            )

            ForEach(store.fixedCapabilities) { capability in
                actionButton(
                    title: capability.name,
                    symbolName: capability.symbolName,
                    isLoading: isExecuting(capability.id)
                ) {
                    store.execute(capability.id)
                }
            }

            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 1, height: 18)
                .padding(.horizontal, 3)

            Button(action: onToggleMore) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .rotationEffect(.degrees(store.isMorePresented ? 45 : 0))
                    .animation(.easeOut(duration: 0.14), value: store.isMorePresented)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(OverlayChromeButtonStyle())
            .help(store.isMorePresented ? "收起更多能力" : "更多能力")
        }
        .padding(4)
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch store.phase {
        case .ready:
            EmptyView()
        case .executing:
            Divider().opacity(0.55)
            statusRow(symbolName: "sparkles", text: "正在执行…", showsProgress: true)
        case let .message(message):
            Divider().opacity(0.55)
            statusRow(symbolName: "checkmark.circle.fill", text: message)
        case let .failure(_, message):
            Divider().opacity(0.55)
            statusRow(symbolName: "exclamationmark.triangle.fill", text: message, isError: true)
        case let .result(_, result):
            Divider().opacity(0.55)
            resultPanel(result)
        case let .translation(capabilityID, request):
            Divider().opacity(0.55)
            if request.providerID == .system, let contextID = store.currentContextID {
                SystemTranslationExecutionView(
                    store: store,
                    capabilityID: capabilityID,
                    contextID: contextID,
                    request: request
                )
                .id(contextID)
            } else {
                statusRow(symbolName: "sparkles", text: "正在请求 AI 翻译…", showsProgress: true)
            }
        }
    }

    private func recommendationRow(_ match: CapabilityMatch) -> some View {
        Button {
            store.execute(match.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: match.capability.symbolName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ClipAllTheme.accent)
                    .frame(width: 22, height: 22)
                    .background(ClipAllTheme.accentSoft, in: RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text("推荐")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ClipAllTheme.accent)
                        Text(match.capability.name)
                            .font(.caption.weight(.semibold))
                        Text("· \(store.pluginName(for: match.capability))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(match.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(OverlayRowButtonStyle())
    }

    private var moreCapabilities: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索插件", text: $store.moreQuery)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        if let first = store.morePluginSections.matches.first {
                            store.execute(first)
                        }
                    }
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(ClipAllTheme.quietFill, in: RoundedRectangle(cornerRadius: 8))

            ScrollView {
                LazyVStack(spacing: 3) {
                    pluginSection(
                        title: store.moreQuery.isEmpty ? "匹配当前内容" : nil,
                        items: store.morePluginSections.matches
                    )
                    if !store.morePluginSections.recent.isEmpty {
                        pluginSection(title: "最近使用的插件", items: store.morePluginSections.recent)
                    }
                    if store.morePluginSections.matches.isEmpty && store.morePluginSections.recent.isEmpty {
                        Text("没有找到插件")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    }
                }
            }
            .frame(idealHeight: moreListHeight, maxHeight: moreListHeight)
        }
        .padding(8)
    }

    private var moreListHeight: CGFloat {
        let sections = store.morePluginSections
        let itemCount = sections.matches.count + sections.recent.count
        guard itemCount > 0 else { return 57 }

        let sectionCount = (sections.matches.isEmpty || !store.moreQuery.isEmpty ? 0 : 1)
            + (sections.recent.isEmpty ? 0 : 1)
        let elementCount = itemCount + sectionCount
        let contentHeight = CGFloat(itemCount * 36 + sectionCount * 18)
            + CGFloat(max(0, elementCount - 1) * 3)
        return min(contentHeight, 176)
    }

    @ViewBuilder
    private func pluginSection(title: String?, items: [PluginDiscoveryItem]) -> some View {
        if let title, !items.isEmpty {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 7)
                .padding(.top, 2)
        }
        ForEach(items) { item in
            Button {
                store.execute(item)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: item.plugin.symbolName)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.plugin.name)
                            .font(.callout.weight(.medium))
                        Text(item.plugin.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "return")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 8)
                .frame(height: 36)
                .contentShape(Rectangle())
            }
            .buttonStyle(OverlayRowButtonStyle())
        }
    }

    private func resultPanel(_ result: CapabilityResult) -> some View {
        ViewThatFits(in: .vertical) {
            resultContent(result)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                resultContent(result)
            }
        }
        .frame(maxHeight: 240)
    }

    private func resultContent(_ result: CapabilityResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(.headline)
                if let subtitle = result.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(result.items) { item in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(item.value)
                            .font(item.style == .monospaced ? .system(.callout, design: .monospaced) : .callout)
                            .textSelection(.enabled)
                        if let annotation = item.annotation {
                            Text(annotation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    Button {
                        store.copyResultItem(item)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(OverlayChromeButtonStyle())
                    .help("复制 \(item.label)")
                }
                .padding(7)
                .background(ClipAllTheme.quietFill, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(9)
    }

    private func actionButton(
        title: String,
        symbolName: String,
        isLoading: Bool,
        action: @escaping () -> Void
    ) -> some View {
        OverlayActionButton(
            title: title,
            symbolName: symbolName,
            isLoading: isLoading,
            action: action
        )
    }

    private func statusRow(
        symbolName: String,
        text: String,
        showsProgress: Bool = false,
        isError: Bool = false
    ) -> some View {
        HStack(spacing: 7) {
            if showsProgress {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: symbolName)
                    .foregroundStyle(isError ? Color.red : ClipAllTheme.accent)
            }
            Text(text)
                .font(.callout)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var isCompactPhase: Bool {
        switch store.phase {
        case .ready, .message:
            true
        default:
            false
        }
    }

    private var cornerRadius: CGFloat {
        ClipAllTheme.Radius.overlayChrome
    }

    private var overlaySurface: Color {
        colorScheme == .dark
            ? Color(red: 0.105, green: 0.11, blue: 0.125).opacity(0.98)
            : Color(nsColor: .windowBackgroundColor).opacity(0.98)
    }

    private var overlayBorder: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.14)
            : Color.black.opacity(0.11)
    }

    private var overlayShadow: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.48)
            : Color.black.opacity(0.16)
    }

    private func isExecuting(_ id: CapabilityID) -> Bool {
        if case let .executing(executingID) = store.phase {
            return executingID == id
        }
        return false
    }
}

private struct OverlayActionButton: View {
    let title: String
    let symbolName: String
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 14)
                } else {
                    Image(systemName: symbolName)
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 14)
                }
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity, minHeight: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(OverlayChromeButtonStyle())
        .accessibilityLabel(title)
    }
}

private struct OverlayChromeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                ZStack {
                    OverlayHoverHighlight(
                        cornerRadius: ClipAllTheme.Radius.overlayChrome,
                        opacity: 0.075
                    )
                    if configuration.isPressed {
                        RoundedRectangle(
                            cornerRadius: ClipAllTheme.Radius.overlayChrome,
                            style: .continuous
                        )
                            .fill(Color.primary.opacity(0.12))
                    }
                }
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }
}

private struct OverlayRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                ZStack {
                    OverlayHoverHighlight(cornerRadius: 8, opacity: 0.07)
                    if configuration.isPressed {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.12))
                    }
                }
            }
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private struct OverlayHoverHighlight: NSViewRepresentable {
    let cornerRadius: CGFloat
    let opacity: CGFloat

    func makeNSView(context: Context) -> OverlayHoverTrackingView {
        OverlayHoverTrackingView(cornerRadius: cornerRadius, highlightOpacity: opacity)
    }

    func updateNSView(_ nsView: OverlayHoverTrackingView, context: Context) {
        nsView.cornerRadius = cornerRadius
        nsView.highlightOpacity = opacity
    }
}

private final class OverlayHoverTrackingView: NSView {
    var cornerRadius: CGFloat {
        didSet { layer?.cornerRadius = cornerRadius }
    }
    var highlightOpacity: CGFloat {
        didSet { updateHighlight() }
    }

    private var trackingAreaReference: NSTrackingArea?
    private var isHighlighted = false

    init(cornerRadius: CGFloat, highlightOpacity: CGFloat) {
        self.cornerRadius = cornerRadius
        self.highlightOpacity = highlightOpacity
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaReference = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        isHighlighted = true
        updateHighlight()
    }

    override func mouseExited(with event: NSEvent) {
        isHighlighted = false
        updateHighlight()
    }

    private func updateHighlight() {
        layer?.backgroundColor = isHighlighted
            ? NSColor.labelColor.withAlphaComponent(highlightOpacity).cgColor
            : NSColor.clear.cgColor
    }
}

@MainActor
private struct SystemTranslationExecutionView: View {
    @ObservedObject var store: SelectionOverlayStore
    let capabilityID: CapabilityID
    let contextID: UUID
    let request: TranslationRequest

    var body: some View {
        HStack(spacing: 9) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text("正在准备设备端翻译…")
                    .font(.callout)
                Text("首次使用某种语言时，macOS 可能会下载语言模型")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .translationTask(
            source: nil,
            target: Locale.Language(identifier: request.targetLanguageIdentifier)
        ) { session in
            do {
                let target = Locale.Language(identifier: request.targetLanguageIdentifier)
                let availability = try await LanguageAvailability().status(
                    for: request.text,
                    to: target
                )
                guard availability != .unsupported else {
                    store.failTranslation(
                        "系统翻译暂不支持这组语言",
                        capabilityID: capabilityID,
                        contextID: contextID
                    )
                    return
                }
                try await session.prepareTranslation()
                try Task.checkCancellation()
                let response = try await session.translate(request.text)
                try Task.checkCancellation()
                let result = SystemTranslationProvider.result(from: response, request: request)
                store.applyTranslationResult(
                    result,
                    capabilityID: capabilityID,
                    contextID: contextID
                )
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                store.failTranslation(
                    SystemTranslationProvider.userMessage(for: error),
                    capabilityID: capabilityID,
                    contextID: contextID
                )
            }
        }
    }
}
