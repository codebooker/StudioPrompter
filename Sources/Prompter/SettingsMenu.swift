import SwiftUI

struct SettingsMenu<Selection: Hashable, Options: View>: View {
    let title: String
    let value: String
    @Binding var selection: Selection
    @ViewBuilder var options: Options
    var body: some View {
        SettingsMenuField(title: title, value: value) {
            Picker(title, selection: $selection) { options }.pickerStyle(.inline)
        }
    }
}

struct SettingsMenuField<Options: View>: View {
    let title: String
    let value: String
    @ViewBuilder var options: Options
    @Environment(\.isEnabled) private var isEnabled
    var body: some View {
        Menu {
            options
        } label: {
            // Native macOS menus flatten custom labels. Draw the field over
            // the menu so it keeps its native keyboard and selection behavior.
            Text(" ")
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden)
        .frame(maxWidth: .infinity).frame(height: 37)
        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            HStack(spacing: 10) {
                Text(value).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Palette.muted)
            }.font(.system(size: 12, weight: .medium)).foregroundStyle(Color.white.opacity(0.9))
                .padding(.horizontal, 12).allowsHitTesting(false).accessibilityHidden(true)
        }
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.border, lineWidth: 1).allowsHitTesting(false))
        .opacity(isEnabled ? 1 : 0.5).accessibilityLabel(title).accessibilityValue(value)
    }
}

