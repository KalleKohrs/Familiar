import FamiliarCore
import FamiliarDesign
import SwiftUI

/// Große Bildansicht mit horizontalem Durchblättern (Guide, Abschnitt 2).
struct ImageGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    let images: [TaskImage]
    @State private var selection: Int

    init(images: [TaskImage], startIndex: Int) {
        self.images = images
        _selection = State(initialValue: min(max(startIndex, 0), max(images.count - 1, 0)))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            TabView(selection: $selection) {
                ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                    TaskImageView(path: image.path, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                        .tag(index)
                        .accessibilityElement()
                        .accessibilityLabel("Bild \(index + 1) von \(images.count)")
                        .accessibilityAddTraits(.isImage)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .always : .never))
            .ignoresSafeArea()

            HStack {
                if images.count > 1 {
                    Text("\(selection + 1) von \(images.count)")
                        .font(FamiliarFont.secondary.monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, FamiliarSpacing.s)
                        .frame(minHeight: 36)
                        .glassEffect(.regular, in: .capsule)
                        .accessibilityHidden(true)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Schließen")
                .accessibilityIdentifier("gallery.close")
            }
            .padding(.horizontal, FamiliarSpacing.m)
            .padding(.top, FamiliarSpacing.xs)
        }
        .statusBarHidden()
    }
}
