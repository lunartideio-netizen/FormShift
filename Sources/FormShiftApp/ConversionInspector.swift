import FormShiftCore
import SwiftUI

struct ConversionInspector: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("输出设置")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text(model.selectedJob == nil ? "应用到等待中的任务" : "当前选择")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 15)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    outputFormatSection
                    outputLocationSection
                    commonSettings
                    advancedSettings
                }
                .padding(20)
            }

            Divider()

            convertFooter
        }
        .background(.ultraThinMaterial)
    }

    private var outputFormatSection: some View {
        InspectorSection(
            title: model.hasMultipleTargets ? "目标格式 · \(model.targetFormats.count) 个" : "目标格式",
            eyebrow: "FORMAT"
        ) {
            Menu {
                ForEach(MediaCategory.allCases, id: \.self) { category in
                    Section(category.displayName) {
                        ForEach(model.formatChoices.filter { $0.category == category }) { format in
                            Button {
                                if model.isTargetFormatSelected(format) {
                                    model.selectTargetFormat(format)
                                } else {
                                    model.addTargetFormat(format)
                                }
                            } label: {
                                if model.isTargetFormatSelected(format) {
                                    Label(format.displayName, systemImage: "checkmark")
                                } else {
                                    Text(format.displayName)
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(FormShiftTheme.cobalt)
                    Text(model.hasMultipleTargets ? "继续添加格式" : "添加目标格式")
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(11)
                .background(FormShiftTheme.cobalt.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(FormShiftTheme.cobalt.opacity(0.20), lineWidth: 1)
                }
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("添加目标格式，当前已选择 \(model.targetFormats.map(\.displayName).joined(separator: "、"))")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                ForEach(model.targetFormats) { format in
                    HStack(spacing: 6) {
                        if model.targetFormat == format {
                            Circle()
                                .fill(FormShiftTheme.formatColor(format.rawValue))
                                .frame(width: 6, height: 6)
                        }
                        Button {
                            model.selectTargetFormat(format)
                        } label: {
                            Text(format.displayName)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(FormShiftTheme.formatColor(format.rawValue))
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("编辑 \(format.displayName) 设置")

                        if model.targetFormats.count > 1 {
                            Button {
                                model.removeTargetFormat(format)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("移除 \(format.displayName) 输出")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(
                        FormShiftTheme.formatColor(format.rawValue)
                            .opacity(model.targetFormat == format ? 0.16 : 0.05),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(
                                FormShiftTheme.formatColor(format.rawValue)
                                    .opacity(model.targetFormat == format ? 0.55 : 0.14),
                                lineWidth: model.targetFormat == format ? 1.2 : 1
                            )
                    }
                }
            }

            if model.hasMultipleTargets {
                Text("每个源文件会分别生成所选格式；不兼容的组合会自动跳过。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var outputLocationSection: some View {
        InspectorSection(title: "保存到", eyebrow: "DESTINATION") {
            InspectorPicker(displayTitle: model.outputLocation.title) {
                ForEach(OutputLocation.allCases) { location in
                    Button {
                        model.outputLocation = location
                    } label: {
                        if model.outputLocation == location {
                            Label(location.title, systemImage: "checkmark")
                        } else {
                            Text(location.title)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text("文件名命名规则")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                TextField("默认: {name} (支持 {name}, {date}, {format})", text: $model.fileNamePattern)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
                HStack(spacing: 6) {
                    Button("{name}_转换") { model.fileNamePattern = "{name}_转换" }.buttonStyle(.borderless).font(.caption2)
                    Button("{name}_{date}") { model.fileNamePattern = "{name}_{date}" }.buttonStyle(.borderless).font(.caption2)
                    Button("重置") { model.fileNamePattern = "" }.buttonStyle(.borderless).font(.caption2)
                }
            }

            Label("重名时自动添加序号", systemImage: "shield.checkered")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var commonSettings: some View {
        InspectorSection(title: "常用设置", eyebrow: "QUICK") {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Text("质量")
                    Spacer()
                    Text(model.quality, format: .percent.precision(.fractionLength(0)))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $model.quality, in: 0.4...1, step: 0.01)
                    .accessibilityLabel("输出质量")
                    .accessibilityValue(Text(model.quality, format: .percent))

                Divider()

                Toggle("智能限制目标体积 (MB)", isOn: $model.targetSizeEnabled)
                    .toggleStyle(.checkbox)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if model.targetSizeEnabled {
                    HStack(spacing: 8) {
                        TextField("目标大小", value: $model.targetFileSizeMB, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .font(.body.monospacedDigit())
                            .frame(width: 80)
                        Text("MB")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    HStack(spacing: 6) {
                        Button("2 MB") { model.targetFileSizeMB = 2.0 }.buttonStyle(.bordered).controlSize(.mini)
                        Button("10 MB 邮件") { model.targetFileSizeMB = 10.0 }.buttonStyle(.bordered).controlSize(.mini)
                        Button("20 MB 微信") { model.targetFileSizeMB = 20.0 }.buttonStyle(.bordered).controlSize(.mini)
                        Button("50 MB") { model.targetFileSizeMB = 50.0 }.buttonStyle(.bordered).controlSize(.mini)
                    }
                }

                Divider()

                Toggle("调整尺寸", isOn: $model.resizeEnabled)
                    .toggleStyle(.checkbox)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if model.resizeEnabled {
                    HStack(spacing: 8) {
                        NumberField(title: "宽", value: $model.width)
                        Text("×")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        NumberField(title: "高", value: $model.height)
                    }

                    if usesImageControls {
                        Picker("尺寸适配", selection: $model.imageSizingMode) {
                            Text("完整适应").tag(ImageSizingMode.fit)
                            Text("填充裁切").tag(ImageSizingMode.fill)
                            Text("拉伸").tag(ImageSizingMode.stretch)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        Text(imageSizingHelp)
                            .font(.caption2)
                            .foregroundStyle(model.imageSizingMode == .stretch ? FormShiftTheme.processAmber : .secondary)
                    } else {
                        Toggle("保持宽高比例", isOn: $model.keepAspectRatio)
                            .toggleStyle(.checkbox)
                    }
                }

                if usesImageControls {
                    Toggle("智能裁剪白边", isOn: $model.trimBorders)
                        .toggleStyle(.checkbox)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Toggle("移除元数据", isOn: $model.removeMetadata)
                    .toggleStyle(.checkbox)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var advancedSettings: some View {
        DisclosureGroup(isExpanded: $model.isAdvancedExpanded) {
            advancedFields
                .padding(.top, 14)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("专业设置")
                    .font(.callout.weight(.semibold))
                Text(advancedSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .panelSurface(radius: 12)
    }

    @ViewBuilder
    private var advancedFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch model.targetFormat.category {
            case .video, .animatedImage:
                InspectorControlRow(label: "编码器") {
                    InspectorPicker(displayTitle: model.codec.rawValue) {
                        ForEach([VideoCodec.automatic, .h264, .hevc, .proRes, .vp9, .av1], id: \.self) { codec in
                            Button {
                                model.codec = codec
                            } label: {
                                if model.codec == codec {
                                    Label(codec.rawValue, systemImage: "checkmark")
                                } else {
                                    Text(codec.rawValue)
                                }
                            }
                        }
                    }
                }

                if model.targetFormat.category == .video {
                    InspectorControlRow(label: "视频码率") {
                        let title: String = {
                            switch model.videoBitrateKbps {
                            case nil: return "自动"
                            case 2500: return "2,500 Kbps (紧凑)"
                            case 4000: return "4,000 Kbps (标准)"
                            case 8000: return "8,000 Kbps (高清)"
                            case 16000: return "16,000 Kbps (超清)"
                            default: return "\(model.videoBitrateKbps!) Kbps"
                            }
                        }()
                        InspectorPicker(displayTitle: title) {
                            Button("自动") { model.videoBitrateKbps = nil }
                            Button("2,500 Kbps (紧凑)") { model.videoBitrateKbps = 2500 }
                            Button("4,000 Kbps (标准)") { model.videoBitrateKbps = 4000 }
                            Button("8,000 Kbps (高清)") { model.videoBitrateKbps = 8000 }
                            Button("16,000 Kbps (超清)") { model.videoBitrateKbps = 16000 }
                        }
                    }
                }

                InspectorControlRow(label: "帧率") {
                    InspectorPicker(displayTitle: "\(model.frameRate) fps") {
                        ForEach([24, 25, 30, 60], id: \.self) { fps in
                            Button("\(fps) fps") { model.frameRate = fps }
                        }
                    }
                }

                InspectorControlRow(label: "") {
                    Toggle("优先使用硬件编码", isOn: $model.hardwareEncoding)
                        .toggleStyle(.checkbox)
                }

                if model.targetFormat.category == .video {
                    mediaTrimmingSection
                    audioSettingsInVideo
                }

            case .audio:
                InspectorControlRow(label: "采样率") {
                    let title: String = {
                        switch model.sampleRate {
                        case 44_100: return "44.1 kHz"
                        case 48_000: return "48 kHz"
                        case 96_000: return "96 kHz"
                        default: return "自动"
                        }
                    }()
                    InspectorPicker(displayTitle: title) {
                        Button("44.1 kHz") { model.sampleRate = 44_100 }
                        Button("48 kHz") { model.sampleRate = 48_000 }
                        Button("96 kHz") { model.sampleRate = 96_000 }
                    }
                }
                InspectorControlRow(label: "声道") {
                    let title: String = {
                        switch model.audioChannels {
                        case 1: return "单声道"
                        case 2: return "立体声"
                        default: return "自动"
                        }
                    }()
                    InspectorPicker(displayTitle: title) {
                        Button("单声道") { model.audioChannels = 1 }
                        Button("立体声") { model.audioChannels = 2 }
                    }
                }
                InspectorControlRow(label: "音频码率") {
                    let title: String = {
                        switch model.audioBitrateKbps {
                        case nil: return "自动"
                        case 96: return "96 Kbps"
                        case 128: return "128 Kbps (标准)"
                        case 192: return "192 Kbps (高质)"
                        case 256: return "256 Kbps (无损级)"
                        case 320: return "320 Kbps (极限)"
                        default: return "\(model.audioBitrateKbps!) Kbps"
                        }
                    }()
                    InspectorPicker(displayTitle: title) {
                        Button("自动") { model.audioBitrateKbps = nil }
                        Button("96 Kbps") { model.audioBitrateKbps = 96 }
                        Button("128 Kbps (标准)") { model.audioBitrateKbps = 128 }
                        Button("192 Kbps (高质)") { model.audioBitrateKbps = 192 }
                        Button("256 Kbps (无损级)") { model.audioBitrateKbps = 256 }
                        Button("320 Kbps (极限)") { model.audioBitrateKbps = 320 }
                    }
                }
                mediaTrimmingSection
                InspectorControlRow(label: "") {
                    Toggle("响度标准化 (EBU R128)", isOn: $model.normalizeAudio)
                        .toggleStyle(.checkbox)
                }

            case .image:
                InspectorControlRow(label: "色彩配置") {
                    let title: String = {
                        switch model.colorProfile {
                        case .automatic: return "自动"
                        case .sRGB: return "sRGB"
                        case .displayP3: return "Display P3"
                        }
                    }()
                    InspectorPicker(displayTitle: title) {
                        Button("自动") { model.colorProfile = .automatic }
                        Button("sRGB") { model.colorProfile = .sRGB }
                        Button("Display P3") { model.colorProfile = .displayP3 }
                    }
                }

                imageTransformFields

                if model.selectedJob?.sourceFormat == .pdf {
                    pdfPageScopeField
                    pdfRenderScaleField
                }

            case .pdf, .document:
                imageTransformFields
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var usesImageControls: Bool {
        model.targetFormat.category == .image || model.targetFormat == .pdf
    }

    private var imageSizingHelp: String {
        switch model.imageSizingMode {
        case .fit: "完整保留画面，不足的一边不会强行撑满。"
        case .fill: "保持比例并铺满尺寸，超出的边缘会居中裁掉。"
        case .stretch: "强制铺满宽高，画面可能变形。"
        }
    }

    private var advancedSubtitle: String {
        switch model.targetFormat.category {
        case .video, .animatedImage: "编码器、码率、裁切与硬件加速"
        case .audio: "采样率、声道、码率与响度"
        case .image, .pdf, .document: "旋转、裁剪与色彩"
        }
    }

    @ViewBuilder
    private var mediaTrimmingSection: some View {
        Toggle("精确起止时间裁切", isOn: $model.trimEnabled)
            .toggleStyle(.checkbox)
            .frame(maxWidth: .infinity, alignment: .leading)
        if model.trimEnabled {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("开始时间 (秒)").font(.caption2).foregroundStyle(.secondary)
                    TextField("0.0", value: $model.trimStartSeconds, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospacedDigit())
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("结束时间 (秒)").font(.caption2).foregroundStyle(.secondary)
                    TextField("0.0", value: $model.trimEndSeconds, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospacedDigit())
                }
            }
        }
    }

    @ViewBuilder
    private var audioSettingsInVideo: some View {
        Toggle("移除音轨 (静音)", isOn: $model.removeAudio)
            .toggleStyle(.checkbox)
            .frame(maxWidth: .infinity, alignment: .leading)
        if !model.removeAudio {
            InspectorControlRow(label: "音频码率") {
                let title: String = {
                    switch model.audioBitrateKbps {
                    case nil: return "自动"
                    case 128: return "128 Kbps (标准)"
                    case 192: return "192 Kbps (高质)"
                    case 256: return "256 Kbps (无损级)"
                    case 320: return "320 Kbps (极限)"
                    default: return "\(model.audioBitrateKbps!) Kbps"
                    }
                }()
                InspectorPicker(displayTitle: title) {
                    Button("自动") { model.audioBitrateKbps = nil }
                    Button("128 Kbps (标准)") { model.audioBitrateKbps = 128 }
                    Button("192 Kbps (高质)") { model.audioBitrateKbps = 192 }
                    Button("256 Kbps (无损级)") { model.audioBitrateKbps = 256 }
                    Button("320 Kbps (极限)") { model.audioBitrateKbps = 320 }
                }
            }
            InspectorControlRow(label: "") {
                Toggle("响度标准化 (EBU R128)", isOn: $model.normalizeAudio)
                    .toggleStyle(.checkbox)
            }
        }
    }

    @ViewBuilder
    private var imageTransformFields: some View {
        InspectorControlRow(label: "旋转") {
            let title = model.rotationDegrees == 0 ? "不旋转" : "\(model.rotationDegrees)°"
            InspectorPicker(displayTitle: title) {
                Button("不旋转") { model.rotationDegrees = 0 }
                Button("90°") { model.rotationDegrees = 90 }
                Button("180°") { model.rotationDegrees = 180 }
                Button("270°") { model.rotationDegrees = 270 }
            }
        }

        if model.selectedJob?.sourceFormat?.category == .image {
            Toggle("手动裁剪", isOn: $model.cropEnabled)
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)

            if model.cropEnabled {
                HStack(spacing: 8) {
                    NumberField(title: "左", value: $model.cropX)
                    NumberField(title: "上", value: $model.cropY)
                }
                HStack(spacing: 8) {
                    NumberField(title: "裁剪宽", value: $model.cropWidth)
                    NumberField(title: "裁剪高", value: $model.cropHeight)
                }
            }
        }
    }

    private var pdfRenderScaleField: some View {
        InspectorControlRow(label: "PDF 精度") {
            let title: String = {
                switch model.pdfImageScale {
                case 1: return "标准 · 1×"
                case 2: return "清晰 · 2×"
                case 3: return "高精度 · 3×"
                default: return "\(model.pdfImageScale)×"
                }
            }()
            InspectorPicker(displayTitle: title) {
                Button("标准 · 1×") { model.pdfImageScale = 1 }
                Button("清晰 · 2×") { model.pdfImageScale = 2 }
                Button("高精度 · 3×") { model.pdfImageScale = 3 }
            }
        }
    }

    @ViewBuilder
    private var pdfPageScopeField: some View {
        InspectorControlRow(label: "导出页面") {
            let title: String = {
                switch model.pdfPageExportScope {
                case .allPages: return "所有页面"
                case .firstPage: return "仅第 1 页"
                case .customRange: return "指定页码"
                }
            }()
            InspectorPicker(displayTitle: title) {
                Button("所有页面") { model.pdfPageExportScope = .allPages }
                Button("仅第 1 页") { model.pdfPageExportScope = .firstPage }
                Button("指定页码") { model.pdfPageExportScope = .customRange }
            }
        }
        if model.pdfPageExportScope == .customRange {
            InspectorControlRow(label: "页码范围") {
                TextField("例如: 1-3, 5, 8", text: $model.pdfCustomPageRange)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
            }
        }
    }

    private var convertFooter: some View {
        VStack(spacing: 10) {
            Button {
                model.startQueue()
            } label: {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text(model.waitingCount > 0 ? "生成 \(model.waitingCount) 个结果" : "添加文件后转换")
                    Spacer()
                    HStack(spacing: 3) {
                        Text("⌘")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        Text("↩")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .shadow(color: FormShiftTheme.cobalt.opacity(model.canStartQueue ? 0.28 : 0), radius: 8, x: 0, y: 4)
            .disabled(!model.canStartQueue)

            Text("文件始终保留在这台 Mac 上")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.bar)
    }
}

private struct InspectorSection<Content: View>: View {
    let title: String
    let eyebrow: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(FormShiftTheme.cobalt)
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(FormShiftTheme.graphite)
            }
            content
        }
    }
}

private struct InspectorControlRow<Control: View>: View {
    let label: String
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .font(.callout.weight(.medium))
                .foregroundStyle(FormShiftTheme.graphite)
                .frame(width: 68, alignment: .trailing)

            control
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NumberField: View {
    let title: String
    @Binding var value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField(title, value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospacedDigit())
                .accessibilityLabel("\(title)度像素")
        }
    }
}
