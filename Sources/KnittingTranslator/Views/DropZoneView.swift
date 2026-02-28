import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    @Binding var droppedURL: URL?
    @Binding var errorMessage: String?
    @Binding var originalFileName: String
    @State private var isTargeted = false
    @State private var showFileImporter = false

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(style: StrokeStyle(lineWidth: 2, dash: [6]))
            .foregroundColor(isTargeted ? .green : .blue)
            .frame(height: 200)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 48))
                        .foregroundColor(.blue)
                    Text(droppedURL?.lastPathComponent ?? "PDFファイルをここにドロップ")
                    Text("または")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("ファイルを選択") { showFileImporter = true }
                        .buttonStyle(.link)
                    if let err = errorMessage {
                        Text(err)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers: providers)
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.pdf]) { result in
                switch result {
                case .success(let url): acceptFile(url: url)
                case .failure(let err): errorMessage = err.localizedDescription
                }
            }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            DispatchQueue.main.async {
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil, isAbsolute: true)
                else { return }
                // Resolve file reference URLs (Finder may provide "file:///.file/id=…" style)
                let resolved = url.resolvingSymlinksInPath()
                guard resolved.pathExtension.lowercased() == "pdf" else {
                    errorMessage = "PDFのみに対応しています"
                    return
                }
                acceptFile(url: resolved)
            }
        }
        return true
    }

    private func acceptFile(url: URL) {
        droppedURL = url
        originalFileName = url.deletingPathExtension().lastPathComponent
        errorMessage = nil
    }
}
