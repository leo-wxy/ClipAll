import AppKit
import SwiftUI
@preconcurrency import Translation

@MainActor
struct SelectionOverlayView: View {
    static let expandedWidth: CGFloat = 324

    @ObservedObject var store: SelectionOverlayStore
    let onToggleMore: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        VStack(spacing: 0) {
            actionBar

            if let recommendation = store.recommendation,
               !store.isMorePresented,
               store.phase == .ready {
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
                .fill(ClipAllTheme.overlaySurface)
                .shadow(
                    color: ClipAllTheme.shadowFloating,
                    radius: ClipAllTheme.Shadow.floatingRadius,
                    y: ClipAllTheme.Shadow.floatingY
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    colorSchemeContrast == .increased
                        ? ClipAllTheme.textSecondary
                        : ClipAllTheme.overlayBorder,
                    lineWidth: colorSchemeContrast == .increased ? 1.25 : 0.75
                )
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
                isActive: false,
                isCapability: false,
                action: store.copySelection
            )

            actionButton(
                title: "粘贴",
                symbolName: "doc.on.clipboard",
                isLoading: false,
                isActive: false,
                isCapability: false,
                action: store.pasteClipboard
            )

            ForEach(store.fixedCapabilities) { capability in
                actionButton(
                    title: capability.name,
                    symbolName: capability.symbolName,
                    isLoading: isExecuting(capability.id),
                    isActive: activeCapabilityID == capability.id,
                    isCapability: true
                ) {
                    store.execute(capability.id)
                }
            }

            Rectangle()
                .fill(ClipAllTheme.separator)
                .frame(width: 1, height: 18)
                .padding(.horizontal, 3)

            Button(action: onToggleMore) {
                Image(
                    systemName: reduceMotion && store.isMorePresented ? "xmark" : "plus"
                )
                    .font(.system(size: 12, weight: .medium))
                    .rotationEffect(
                        .degrees(!reduceMotion && store.isMorePresented ? 45 : 0)
                    )
                    .animation(
                        reduceMotion ? nil : .easeOut(duration: 0.14),
                        value: store.isMorePresented
                    )
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
                    .background(
                        ClipAllTheme.accentSoft,
                        in: RoundedRectangle(
                            cornerRadius: ClipAllTheme.Radius.control,
                            style: .continuous
                        )
                    )

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
        isActive: Bool,
        isCapability: Bool,
        action: @escaping () -> Void
    ) -> some View {
        OverlayActionButton(
            title: title,
            symbolName: symbolName,
            isLoading: isLoading,
            isActive: isActive,
            isCapability: isCapability,
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
                    .foregroundStyle(isError ? ClipAllTheme.error : ClipAllTheme.accent)
            }
            Text(text)
                .font(.callout)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var cornerRadius: CGFloat {
        ClipAllTheme.Radius.overlayChrome
    }

    private func isExecuting(_ id: CapabilityID) -> Bool {
        if case let .executing(executingID) = store.phase {
            return executingID == id
        }
        return false
    }

    private var activeCapabilityID: CapabilityID? {
        switch store.phase {
        case .ready:
            nil
        case let .failure(capabilityID, _):
            capabilityID
        case let .executing(capabilityID):
            capabilityID
        case let .result(capabilityID, _):
            capabilityID
        case let .translation(capabilityID, _):
            capabilityID
        }
    }
}

private struct OverlayActionButton: View {
    let title: String
    let symbolName: String
    let isLoading: Bool
    let isActive: Bool
    let isCapability: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 14)
                } else {
                    ClipAllToolbarGlyph(
                        symbolName: symbolName,
                        isAccented: isCapability && !isActive
                    )
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
        .buttonStyle(OverlayChromeButtonStyle(isActive: isActive))
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityLabel(title)
    }
}

private struct OverlayChromeButtonStyle: ButtonStyle {
    var isActive = false

    func makeBody(configuration: Configuration) -> Body {
        Body(configuration: configuration, isActive: isActive)
    }

    fileprivate struct Body: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        let configuration: Configuration
        let isActive: Bool

        var body: some View {
            configuration.label
                .foregroundStyle(isActive ? ClipAllTheme.onAccent : ClipAllTheme.textPrimary)
                .background {
                    ZStack {
                        if isActive {
                            RoundedRectangle(
                                cornerRadius: ClipAllTheme.Radius.overlayChrome,
                                style: .continuous
                            )
                            .fill(ClipAllTheme.accent)
                        }
                        ClipAllHoverHighlight(
                            cornerRadius: ClipAllTheme.Radius.overlayChrome,
                            opacity: isActive
                                ? ClipAllTheme.Interaction.activeChromeHoverOpacity
                                : ClipAllTheme.Interaction.chromeHoverOpacity
                        )
                        if configuration.isPressed {
                            RoundedRectangle(
                                cornerRadius: ClipAllTheme.Radius.overlayChrome,
                                style: .continuous
                            )
                            .fill(
                                isActive
                                    ? ClipAllTheme.accentPressedFill
                                    : ClipAllTheme.overlayPressedFill
                            )
                        }
                    }
                }
                .overlay {
                    if isFocused {
                        RoundedRectangle(
                            cornerRadius: ClipAllTheme.Radius.overlayChrome,
                            style: .continuous
                        )
                        .stroke(ClipAllTheme.focusRing, lineWidth: 2)
                    }
                }
                .scaleEffect(!reduceMotion && configuration.isPressed ? 0.97 : 1)
                .opacity(
                    isEnabled ? 1 : ClipAllTheme.Interaction.disabledOpacity
                )
                .animation(
                    reduceMotion ? nil : .easeOut(duration: 0.10),
                    value: configuration.isPressed
                )
        }
    }
}

private struct OverlayRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> Body {
        Body(configuration: configuration)
    }

    fileprivate struct Body: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.isFocused) private var isFocused
        let configuration: Configuration

        var body: some View {
            configuration.label
                .background {
                    ZStack {
                        ClipAllHoverHighlight(
                            cornerRadius: ClipAllTheme.Radius.control,
                            opacity: ClipAllTheme.Interaction.chromeHoverOpacity
                        )
                        if configuration.isPressed {
                            RoundedRectangle(
                                cornerRadius: ClipAllTheme.Radius.control,
                                style: .continuous
                            )
                            .fill(ClipAllTheme.overlayPressedFill)
                        }
                    }
                }
                .overlay {
                    if isFocused {
                        RoundedRectangle(
                            cornerRadius: ClipAllTheme.Radius.control,
                            style: .continuous
                        )
                        .stroke(ClipAllTheme.focusRing, lineWidth: 2)
                    }
                }
                .animation(
                    reduceMotion ? nil : .easeOut(duration: 0.08),
                    value: configuration.isPressed
                )
        }
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
