import SwiftUI

struct InfoView: View {
    @Environment(\.dismiss) private var dismiss

    let markdownText = NSLocalizedString("app_description", comment: "App description markdown text")
    
    var body: some View {
        NavigationStack {
            ScrollView {
                 VStack(alignment: .leading, spacing: 16) {
                     ForEach(markdownText.components(separatedBy: "\n\n"), id: \.self) { block in
                         if let attr = try? AttributedString(markdown: block) {
                             Text(attr)
                                 .frame(maxWidth: .infinity, alignment: .leading)
                         }
                     }
                 }
                 .padding()
            }
            
            .navigationTitle(NSLocalizedString("app_info_title", comment: "App info screen title"))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("done_button", comment: "Done button title")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    InfoView()
}
