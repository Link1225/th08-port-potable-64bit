import SwiftUI
import UniformTypeIdentifiers

struct BringUpView: View {
    @Environment(\.scenePhase) private var scenePhase
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

                TH08IOSRendererPreview()
                    .frame(height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Text("OpenGL ES renderer preview — the original game engine is not running here yet.")
                    .font(.caption)
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
            .onChange(of: scenePhase) { phase in
                if phase != .active {
                    TH08IOSClearKeyboardState()
                }
            }
            .task {
                let existingDirectory = await Task.detached(priority: .utility) {
                    TH08DataArchiveImport.existingDirectory()
                }.value
                if let directory = existingDirectory {
                    do {
                        try TH08DataArchiveImport.activateEngineDataDirectory(at: directory)
                        importedDirectory = directory
                        status = "Both original archives are valid. The engine data directory is active."
                    } catch {
                        status = error.localizedDescription
                    }
                }
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            status = "Import cancelled or failed: \(error.localizedDescription)"
        case .success(let urls):
            isImporting = true
            status = "Importing archives…"
            Task {
                do {
                    let directory = try await Task.detached(priority: .userInitiated) {
                        try TH08DataArchiveImport.installPair(from: urls)
                    }.value
                    try TH08DataArchiveImport.activateEngineDataDirectory(at: directory)
                    importedDirectory = directory
                    status = "Both archives were imported and the engine data directory is active."
                } catch {
                    status = error.localizedDescription
                }
                isImporting = false
            }
        }
    }
}
