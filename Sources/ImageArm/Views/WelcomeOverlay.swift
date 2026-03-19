import SwiftUI

struct WelcomeOverlay: View {
    @Binding var hasSeenWelcome: Bool

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(.tint)

            Text("Bienvenue dans ImageArm")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Glissez vos images ou cliquez + pour commencer.\nImageArm optimise PNG, JPEG, HEIF, GIF, TIFF, AVIF, SVG et WebP.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Commencer") {
                hasSeenWelcome = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(DesignTokens.Spacing.xl)
        .frame(maxWidth: 400)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 20)
    }
}
