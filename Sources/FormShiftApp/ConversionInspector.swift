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
                        Button {
                            model.selectTargetFormat(format)
                        } label: {
                            Text(format.displayName)
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
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
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("移除 \(format.displayName) 输出")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        FormShiftTheme.formatColor(format.rawValue)
                            .opacity(model.targetFormat == format ? 0.14 : 0.06),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(
                                FormShiftTheme.formatColor(format.rawValue)
                                    .opacity(model.targetFormat == format ? 0.42 : 0.16),
                                lineWidth: model.targetFormat == format ? 1.5 : 1
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
            Picker("保存位置", selection: $model.outputLocation) {
                ForEach(OutputLocation.allCases) { location in
                    Text(location.title).tag(location)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)

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
                    Picker("编码器", selection: $model.codec) {
                        Text("自动").tag(VideoCodec.automatic)
                        Text("H.264").tag(VideoCodec.h264)
                        Text("HEVC").tag(VideoCodec.hevc)
                        Text("ProRes").tag(VideoCodec.proRes)
                        Text("VP9").tag(VideoCodec.vp9)
                        Text("AV1").tag(VideoCodec.av1)
                    }
                    .labelsHidden()
                }

                InspectorControlRow(label: "帧率") {
                    Picker("帧率", selection: $model.frameRate) {
                        Text("24 fps").tag(24)
                        Text("25 fps").tag(25)
                        Text("30 fps").tag(30)
                        Text("60 fps").tag(60)
                    }
                    .labelsHidden()
                }

                InspectorControlRow(label: "") {
                    Toggle("优先使用硬件编码", isOn: $model.hardwareEncoding)
                        .toggleStyle(.checkbox)
                }

            case .audio:
                InspectorControlRow(label: "采样率") {
                    Picker("采样率", selection: $model.sampleRate) {
                        Text("44.1 kHz").tag(44_100)
                        Text("48 kHz").tag(48_000)
                        Text("96 kHz").tag(96_000)
                    }
                    .labelsHidden()
                }
                InspectorControlRow(label: "声道") {
                    Picker("声道", selection: $model.audioChannels) {
                        Text("单声道").tag(1)
                        Text("立体声").tag(2)
                    }
                    .labelsHidden()
                }

            case .image:
                InspectorControlRow(label: "色彩配置") {
                    Picker("色彩配置", selection: $model.colorProfile) {
                        Text("自动").tag(ImageColorProfile.automatic)
                        Text("sRGB").tag(ImageColorProfile.sRGB)
                        Text("Display P3").tag(ImageColorProfile.displayP3)
                    }
                    .labelsHidden()
                }

                imageTransformFields

                if model.selectedJob?.sourceFormat == .pdf {
                    pdfRenderScaleField
                }

            case .pdf:
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
        case .video, .animatedImage: "编码器、帧率与硬件加速"
        case .audio: "采样率与声道"
        case .image, .pdf: "旋转、裁剪与色彩"
        }
    }

    @ViewBuilder
    private var imageTransformFields: some View {
        InspectorControlRow(label: "旋转") {
            Picker("旋转角度", selection: $model.rotationDegrees) {
                Text("不旋转").tag(0)
                Text("90°").tag(90)
                Text("180°").tag(180)
                Text("270°").tag(270)
            }
            .labelsHidden()
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
            Picker("页面渲染精度", selection: $model.pdfImageScale) {
                Text("标准 · 1×").tag(1)
                Text("清晰 · 2×").tag(2)
                Text("高精度 · 3×").tag(3)
            }
            .labelsHidden()
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
                    Text("⌘↩")
                        .font(.caption.monospaced())
                        .foregroundStyle(.white.opacity(0.72))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
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
