import SwiftUI

/// 十段均衡器：31Hz–16kHz、七套预设、前级与总开关。
struct EqualizerSheet: View {
    @EnvironmentObject var player: PlayerStore
    @Environment(\.dismiss) private var dismiss

    private var theme: Theme { player.theme }

    var body: some View {
        ZStack {
            theme.pageBackground.ignoresSafeArea()
            VStack(spacing: 13) {
                header
                presets
                bandsPanel
                preampRow
                footer
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: 顶部

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("十段均衡器")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(theme.textPrimary)
                Text(player.equalizer.enabled ? "已开启 · \(player.equalizer.presetName)" : "旁路中 · \(player.equalizer.presetName)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(player.equalizer.enabled ? theme.accent : theme.textTertiary)
            }
            Spacer(minLength: 6)
            Toggle("", isOn: Binding(
                get: { player.equalizer.enabled },
                set: { value in
                    player.equalizer.enabled = value
                }
            ))
            .labelsHidden()
            .tint(theme.accent)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: 预设

    private var presets: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(EqualizerSettings.presets) { preset in
                    let active = player.equalizer.presetName == preset.name
                    Button {
                        var settings = player.equalizer
                        settings.apply(preset: preset)
                        settings.enabled = true
                        player.equalizer = settings
                    } label: {
                        Text(preset.name)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(active ? theme.pageBottom : theme.textSecondary)
                            .padding(.horizontal, 11)
                            .frame(height: 26)
                            .background(
                                Capsule()
                                    .fill(active ? theme.accentSoft.opacity(0.92) : Color.white.opacity(0.06))
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(theme.windowBorder.opacity(active ? 0 : 0.45), lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 1)
        }
        .frame(height: 30)
    }

    // MARK: 推子

    private var bandsPanel: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 2) {
                ForEach(0..<EqualizerSettings.frequencies.count, id: \.self) { index in
                    VStack(spacing: 4) {
                        Text(gainLabel(index))
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundColor(abs(gain(index)) > 0.1 ? theme.accent : theme.textTertiary)
                        VerticalSlider(value: bandBinding(index), range: -12...12, theme: theme)
                            .frame(height: 148)
                        Text(EqualizerSettings.frequencyLabels[index])
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundColor(theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 6)

            HStack {
                Text("-12")
                Spacer()
                Text("0 dB")
                Spacer()
                Text("+12")
            }
            .font(.system(size: 8, weight: .medium, design: .monospaced))
            .foregroundColor(theme.textTertiary)
            .padding(.horizontal, 10)
            .padding(.bottom, 2)
        }
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(theme.isClassic ? 0.08 : 0.26))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(theme.windowBorder.opacity(0.4), lineWidth: 1)
        )
        .opacity(player.equalizer.enabled ? 1 : 0.55)
    }

    // MARK: 前级

    private var preampRow: some View {
        HStack(spacing: 10) {
            Text("前级")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(theme.textSecondary)
            Slider(value: Binding(
                get: { Double(player.equalizer.preamp) },
                set: { value in
                    player.equalizer.preamp = Float((value * 2).rounded() / 2)
                }
            ), in: -12...12)
            .tint(theme.accent)
            Text(String(format: "%+.1f dB", Double(player.equalizer.preamp)))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(theme.textSecondary)
                .frame(width: 56, alignment: .trailing)
        }
    }

    // MARK: 底部

    private var footer: some View {
        HStack(spacing: 8) {
            TTSmallButton(title: "重置", theme: theme) {
                var settings = player.equalizer
                settings.reset()
                player.equalizer = settings
            }
            Spacer(minLength: 2)
            Text("打开锁屏/后台播放时同样生效")
                .font(.system(size: 9))
                .foregroundColor(theme.textTertiary)
            TTSmallButton(title: "完成", theme: theme, filled: true) {
                dismiss()
            }
        }
    }

    private func gain(_ index: Int) -> Double {
        guard index < player.equalizer.gains.count else { return 0 }
        return Double(player.equalizer.gains[index])
    }

    private func gainLabel(_ index: Int) -> String {
        let value = gain(index)
        if abs(value) < 0.05 { return "0" }
        return String(format: "%+.0f", value)
    }

    private func bandBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: { gain(index) },
            set: { newValue in
                var settings = player.equalizer
                guard index < settings.gains.count else { return }
                settings.gains[index] = Float((newValue * 2).rounded() / 2)
                settings.presetName = "自定义"
                player.equalizer = settings
            }
        )
    }
}
