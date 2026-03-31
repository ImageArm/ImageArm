import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: ImageStore
    @State private var tools: [ToolManager.ToolInfo] = []

    var body: some View {
        TabView {
            optimizationTab
                .tabItem { Label("Optimisation", systemImage: "slider.horizontal.3") }

            toolsTab
                .tabItem { Label("Outils", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 540, height: 620)
        .task { tools = await Task.detached { ToolManager().allTools() }.value }
    }

    // MARK: - Optimization Tab

    private var optimizationTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Level selector
            VStack(alignment: .leading, spacing: 12) {
                Text("Niveau d'optimisation")
                    .font(.headline)

                HStack(spacing: 0) {
                    ForEach(OptimizationLevel.allCases) { level in
                        LevelButton(level: level, isSelected: store.level == level) {
                            store.level = level
                        }
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
            }
            .padding()

            Divider()

            // Detail panel for selected level
            LevelDetailView(level: store.level)
                .padding()

            Divider()

            // Custom quality overrides
            Form {
                Section("Qualité personnalisée") {
                    Toggle("Utiliser des réglages manuels (ignorer le niveau)", isOn: $store.useCustomQuality)

                    if store.useCustomQuality {
                        // PNG
                        Toggle("PNG : compression avec perte", isOn: $store.pngLossyOverride)
                        if store.pngLossyOverride {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Qualité PNG")
                                    Spacer()
                                    Text("\(Int(store.pngQualityCustom))%")
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                                Slider(value: $store.pngQualityCustom, in: 30...100, step: 5)
                            }
                        }

                        Divider()

                        // JPEG
                        Toggle("JPEG : compression avec perte", isOn: $store.jpegLossyOverride)
                        if store.jpegLossyOverride {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Qualité JPEG")
                                    Spacer()
                                    Text("\(Int(store.jpegQualityCustom))%")
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                                Slider(value: $store.jpegQualityCustom, in: 30...100, step: 5)
                            }
                        }
                    }
                }

                Section("Performance") {
                    Picker("Optimisations simultanées", selection: $store.maxConcurrent) {
                        Text("2").tag(2)
                        Text("4").tag(4)
                        Text("8").tag(8)
                        Text("16").tag(16)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal)

            Spacer()
        }
    }

    // MARK: - Tools Tab

    private var toolsTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Outils d'optimisation installés")
                .font(.headline)
                .padding()

            List(tools, id: \.name) { tool in
                HStack {
                    Image(systemName: tool.isAvailable ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(tool.isAvailable ? .green : .red)

                    VStack(alignment: .leading) {
                        Text(tool.name)
                        if let path = tool.path {
                            Text(path)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Spacer()

                    if !tool.isAvailable {
                        Button("Copier install") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(tool.installCommand, forType: .string)
                        }
                        .font(.caption)
                        .help(tool.installCommand)
                    }
                }
            }

            HStack {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text("Les outils CLI sont embarqués dans l'application.")
                Button("Voir les licences") {
                    // Bundle: Contents/Resources/LICENSES, Dev: ./LICENSES
                    let candidates = [
                        Bundle.main.resourceURL?.appendingPathComponent("LICENSES"),
                        Bundle.main.bundleURL.appendingPathComponent("LICENSES"),
                        URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/LICENSES"),
                    ]
                    if let url = candidates.compactMap({ $0 }).first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}

// MARK: - Level Button

struct LevelButton: View {
    let level: OptimizationLevel
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: level.icon)
                    .font(.title2)
                Text(level.name)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? Color.accentColor.opacity(0.15) : .clear)
            .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Level Detail

struct LevelDetailView: View {
    let level: OptimizationLevel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: level.icon)
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                Text(level.name)
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Text(level.estimatedTime)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(Capsule())
            }

            Text(level.description)
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("PNG").font(.caption).fontWeight(.bold).foregroundStyle(.blue)
                    settingRow(items: pngDetails)
                }
                GridRow {
                    Text("JPEG").font(.caption).fontWeight(.bold).foregroundStyle(.orange)
                    settingRow(items: jpegDetails)
                }
                GridRow {
                    Text("Méta").font(.caption).fontWeight(.bold).foregroundStyle(.gray)
                    Text(level.stripMetadata ? "Suppression EXIF, commentaires, profils" : "Conservation des métadonnées")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var pngDetails: [String] {
        var items: [String] = []
        if level.pngLossy && level.useGPU {
            items.append("🔲 Metal GPU quantize")
        }
        if level.pngLossy {
            let (minQ, maxQ) = level.pngQuantQualityRange
            items.append("pngquant \(minQ)-\(maxQ)%")
        }
        items.append("oxipng -o\(level.oxipngLevel)")
        return items
    }

    private var jpegDetails: [String] {
        var items: [String] = []
        if level.jpegLossy && level.useGPU {
            items.append("🔲 Metal HW encoder")
        }
        items.append("mozjpeg" + (level.jpegProgressive ? " progressive" : ""))
        return items
    }

    private func settingRow(items: [String]) -> some View {
        HStack(spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.system(size: 10, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }
}
