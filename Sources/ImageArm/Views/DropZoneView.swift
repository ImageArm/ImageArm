import SwiftUI

struct DropZoneView: View {
    @Binding var isDragOver: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Glissez vos images ici")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text("ou cliquez + pour ajouter des fichiers")
                .font(.subheadline)
                .foregroundStyle(.tertiary)

            Text("PNG · JPEG · HEIF · SVG · WebP")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                .foregroundStyle(isDragOver ? Color.blue : Color.gray.opacity(0.3))
                .padding(20)
        }
        .background(isDragOver ? Color.accentColor.opacity(0.05) : .clear)
        .animation(.easeInOut(duration: 0.2), value: isDragOver)
    }
}
