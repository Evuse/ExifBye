import SwiftUI

struct ContentView: View {
    @StateObject private var model = BatchModel()
    @State private var showPicker = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "sparkles.rectangle.stack.fill")
                            .font(.system(size: 38)).foregroundStyle(.tint)
                            .accessibilityHidden(true)
                        Text("I tuoi ricordi, senza metadati.")
                            .font(.title2.bold())
                        Text("Seleziona foto e video. Salva nuove copie pulite nel rullino, lasciando intatti gli originali.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 12)
                    Button { showPicker = true } label: {
                        Label(model.items.isEmpty ? "Seleziona foto e video" : "Nuova selezione",
                              systemImage: "photo.on.rectangle.angled")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                    }
                    .disabled(model.isBusy)
                }

                if !model.items.isEmpty {
                    Section {
                        LabeledContent("Selezionati", value: "\(model.items.count)")
                        LabeledContent("Copie salvate", value: "\(model.savedCount)")
                        if model.failedCount > 0 {
                            LabeledContent("Da riprovare", value: "\(model.failedCount)")
                        }
                        if model.isBusy {
                            if let index = model.activeIndex {
                                Text("Elemento \(index + 1) di \(model.items.count)").font(.headline)
                            }
                            if model.stage.hasPrefix("Importazione") {
                                ProgressView().accessibilityLabel("Importazione in corso")
                            } else {
                                ProgressView(value: model.fraction)
                                    .accessibilityLabel("Avanzamento elemento")
                            }
                            Text(model.stage).font(.subheadline).foregroundStyle(.secondary)
                            Button(role: .destructive) { model.stop() } label: {
                                Text(model.isStopping ? "Interruzione in corso…" : "Interrompi")
                            }
                            .disabled(model.isStopping)
                        } else {
                            if !model.stage.isEmpty { Text(model.stage).font(.subheadline) }
                            if model.remainingCount > 0 {
                                Button { model.start() } label: {
                                    Text(model.savedCount == 0 ? "Pulisci e salva" : "Riprendi / riprova rimasti")
                                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                                }
                                .buttonStyle(.borderedProminent)
                            } else {
                                Label("Tutte le copie sono nel rullino", systemImage: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }

                    Section("Elementi") {
                        ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                            HStack(alignment: .top, spacing: 12) {
                                statusIcon(item.state).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Elemento \(index + 1)")
                                    Text(statusText(item.state)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("Come funziona") {
                    Label("Nessun account. Nessun server dell’app.", systemImage: "iphone.gen3")
                    Label("Selezione multipla senza limite imposto dall’app.", systemImage: "square.stack.3d.up")
                    Text("Le immagini diventano JPEG e i video MP4 (H.264/AAC), in SDR. Le Live Photo diventano foto statiche. La ricodifica può ridurre la qualità; servono tempo e spazio libero.")
                    Text("Rimangono i dati tecnici necessari a leggere il file. Volti, targhe, scritte e informazioni udibili non vengono cancellati. Foto crea una nuova data di salvataggio nel rullino.")
                    Text("Tieni l’app aperta durante la pulizia. Passando in background il lavoro si interrompe; puoi riprendere i file rimasti. Gli elementi su iCloud possono richiedere un download; le copie salvate seguono le impostazioni di sincronizzazione di Foto.")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .navigationTitle("ExifBye")
            .sheet(isPresented: $showPicker) {
                MediaPicker { results in
                    model.select(results)
                    showPicker = false
                }.ignoresSafeArea()
            }
            .alert("ExifBye", isPresented: Binding(
                get: { model.message != nil }, set: { if !$0 { model.message = nil } }
            )) {
                Button("OK", role: .cancel) { model.message = nil }
            } message: { Text(model.message ?? "") }
            .onChange(of: scenePhase) { phase in
                if phase == .background { model.stop() }
            }
        }
        .tint(.teal)
    }

    @ViewBuilder
    private func statusIcon(_ state: BatchItem.State) -> some View {
        switch state {
        case .pending: Image(systemName: "circle").foregroundStyle(.secondary)
        case .working: ProgressView()
        case .saved: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
        }
    }

    private func statusText(_ state: BatchItem.State) -> String {
        switch state {
        case .pending: return "In attesa"
        case .working: return "In elaborazione"
        case .saved: return "Copia clean salvata"
        case .failed(let reason): return reason
        }
    }
}
