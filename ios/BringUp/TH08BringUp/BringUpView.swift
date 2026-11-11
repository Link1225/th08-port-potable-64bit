import SwiftUI
import UniformTypeIdentifiers

struct BringUpView: View {
    @State private var isImporterPresented = false
    @State private var status = "Import the two original data archives from your own CD."
    @State private var importedDirectory: URL?
    @State private var isImporting = false

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Touhou 8 — Imperishable Night")
                    .font(.title2.weight(.semibold))

                Text("This app currently prepares your game data. The original game engine is not connected yet.")
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Label("th08.dat", systemImage: "doc")
                    Label("thbgm.dat", systemImage: "music.note")
                }
                .font(.body)

                Button {
                    isImporterPresented = true
                } label: {
                    Label("Import both data files", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isImporting)

                if isImporting {
                    ProgressView()
                }

                Text(status)
                    .font(.callout)
                    .textSelection(.enabled)

                if let directory = importedDirectory {
                    Text("Stored in: \(directory.lastPathComponent)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding()
            .background(KeyboardCaptureView())
            .navigationTitle("TH08 iOS")
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [.data],
                allowsMultipleSelection: true,
                onCompletion: handleImport
            )
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            status = "Import cancelled or failed: \(error.localizedDescription)"
        case .success(let urls):
            isImporting = true
            status = "Importing archives…"
            do {
                let directory = try TH08DataArchiveImport.installPair(from: urls)
                importedDirectory = directory
                status = "Both archives were imported successfully."
            } catch {
                status = error.localizedDescription
            }
            isImporting = false
        }
    }
}
