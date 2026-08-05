import SwiftUI
import AppKit
@preconcurrency import ScreenCaptureKit

struct SubtitleLine: Identifiable, Equatable {
    let id = UUID()
    let originalText: String
    var translatedText: String?
    let timestamp = Date()
}

@MainActor
class TranslatorViewModel: ObservableObject, AudioCaptureDelegate, LocalSTTDelegate, LocalTranslationDelegate {
    @Published var status: String = "未啟動"
    @Published var subtitleHistory: [SubtitleLine] = []
    @Published var showBilingual = true

    @Published var shareableApps: [SCRunningApplication] = []
    @Published var selectedApp: SCRunningApplication?

    // WhisperKit model name -- tiny/base/small all validated in the Phase 0 spike.
    @Published var selectedModel = "small"
    // Gemma 4 size -- e2b is the Phase 0 spike's recommended default (half the
    // latency of e4b, comparable quality on the tested sentences).
    @Published var translationModel = "e2b"

    @Published var isRunning = false

    private let captureManager = AudioCaptureManager()
    private let sttEngine = LocalSTTEngine()
    private let translationEngine = LocalTranslationEngine()

    init() {
        captureManager.delegate = self
        if let savedModel = UserDefaults.standard.string(forKey: "WhisperModel") {
            self.selectedModel = savedModel
        }
        if let savedTranslationModel = UserDefaults.standard.string(forKey: "TranslationModel") {
            self.translationModel = savedTranslationModel
        }
    }

    func refreshApps() {
        Task {
            let result = await captureManager.fetchShareableApps()
            self.shareableApps = result.apps
            if let errMsg = result.error {
                self.status = errMsg
            }
            if self.selectedApp == nil, let firstApp = result.apps.first(where: {
                let name = $0.applicationName
                return name.contains("Zoom") || name.contains("Chrome") || name.contains("Safari") || name.contains("Meet") || name.contains("Teams")
            }) {
                self.selectedApp = firstApp
            } else if self.selectedApp == nil {
                self.selectedApp = result.apps.first
            }
        }
    }

    func start() {
        guard let app = selectedApp else {
            status = "錯誤：請選擇要擷取音訊的應用程式"
            return
        }

        UserDefaults.standard.set(selectedModel, forKey: "WhisperModel")
        UserDefaults.standard.set(translationModel, forKey: "TranslationModel")

        isRunning = true
        subtitleHistory = []

        Task {
            await sttEngine.setDelegate(self)
            await translationEngine.setDelegate(self)
            // Language left nil (auto-detect) for now -- Phase 0 found this misfires on
            // short/synthetic audio; a future pass should let the user pin a language.
            // Tracked as an open risk in the feasibility doc.
            async let sttReady: Void = sttEngine.start(modelName: selectedModel, language: nil)
            async let translationReady: Void = translationEngine.start(modelSize: translationModel)
            _ = await (sttReady, translationReady)
            await captureManager.startCapture(for: app)
        }
    }

    func stop() {
        isRunning = false
        Task {
            await captureManager.stopCapture()
            await sttEngine.stop()
            await translationEngine.stop()
        }
        status = "已停止"
    }

    // MARK: - AudioCaptureDelegate
    nonisolated func didCaptureAudioData(_ data: Data) {
        sttEngine.append(pcm16Data: data)
    }

    nonisolated func didUpdateApplications(_ apps: [SCRunningApplication]) {
        Task { @MainActor in
            self.shareableApps = apps
        }
    }

    // MARK: - LocalSTTDelegate
    nonisolated func didTranscribeSegment(_ text: String) {
        Task { @MainActor in
            let line = SubtitleLine(originalText: text, translatedText: nil)
            self.subtitleHistory.append(line)
            let lineID = line.id

            let translated = await self.translationEngine.translate(text)
            if let index = self.subtitleHistory.firstIndex(where: { $0.id == lineID }) {
                self.subtitleHistory[index].translatedText = translated ?? "（翻譯失敗）"
            }
        }
    }

    nonisolated func didUpdateSTTStatus(_ status: String) {
        Task { @MainActor in
            self.status = status
        }
    }

    // MARK: - LocalTranslationDelegate
    nonisolated func didUpdateTranslationStatus(_ status: String) {
        Task { @MainActor in
            self.status = status
        }
    }
}

struct ContentView: View {
    @ObservedObject var viewModel: TranslatorViewModel

    var body: some View {
        VStack(spacing: 14) {
            Text("會議即時雙語字幕（本地 STT + Gemma 4 翻譯）")
                .font(.title2)
                .bold()
                .padding(.top)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("1. WhisperKit 模型")
                        .font(.headline)
                    Picker("模型", selection: $viewModel.selectedModel) {
                        Text("tiny（最快）").tag("tiny")
                        Text("base").tag("base")
                        Text("small（建議）").tag("small")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .disabled(viewModel.isRunning)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text("2. Gemma 4 翻譯模型")
                        .font(.headline)
                    Picker("翻譯模型", selection: $viewModel.translationModel) {
                        Text("E2B（建議，較快）").tag("e2b")
                        Text("E4B（較準確）").tag("e4b")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .disabled(viewModel.isRunning)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("3. 選擇會議來源 App")
                            .font(.headline)
                        Spacer()
                        Button(action: { viewModel.refreshApps() }) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        .disabled(viewModel.isRunning)
                    }
                    Picker("目標 App", selection: $viewModel.selectedApp) {
                        if viewModel.shareableApps.isEmpty {
                            Text("點擊重新整理").tag(nil as SCRunningApplication?)
                        } else {
                            ForEach(viewModel.shareableApps, id: \.processID) { app in
                                Text(app.applicationName).tag(app as SCRunningApplication?)
                            }
                        }
                    }
                    .pickerStyle(DefaultPickerStyle())
                    .disabled(viewModel.isRunning)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Toggle("顯示雙語對照（原文 / 中文）", isOn: $viewModel.showBilingual)
                    .toggleStyle(CheckboxToggleStyle())
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal)

            HStack {
                Spacer()
                if !viewModel.isRunning {
                    Button(action: { viewModel.start() }) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("開始")
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 20)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                } else {
                    Button(action: { viewModel.stop() }) {
                        HStack {
                            Image(systemName: "stop.fill")
                            Text("停止")
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 20)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                }
            }
            .padding(.horizontal)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("狀態：")
                        .font(.subheadline)
                        .bold()
                    Text(viewModel.status)
                        .font(.subheadline)
                        .foregroundColor(viewModel.isRunning ? .green : .gray)
                    Spacer()
                }

                Text("即時翻譯字幕：")
                    .font(.headline)

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(viewModel.subtitleHistory) { line in
                                VStack(alignment: .leading, spacing: 4) {
                                    if viewModel.showBilingual {
                                        Text(line.originalText)
                                            .foregroundColor(.gray)
                                            .font(.system(size: 14, design: .monospaced))
                                    }
                                    Text(line.translatedText ?? "翻譯中...")
                                        .foregroundColor(line.translatedText == nil ? .secondary : .primary)
                                        .font(.system(size: 16, weight: .medium))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line.id)
                            }

                            if viewModel.subtitleHistory.isEmpty {
                                Text("等待音訊輸入...（請確保選擇正確的會議 App 並在該 App 中有聲音播放）")
                                    .foregroundColor(.gray)
                                    .font(.italic(.system(size: 14))())
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding()
                    }
                    .background(Color(NSColor.windowBackgroundColor))
                    .cornerRadius(8)
                    .border(Color.gray.opacity(0.2), width: 1)
                    .onChange(of: viewModel.subtitleHistory) {
                        if let last = viewModel.subtitleHistory.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .padding([.horizontal, .bottom])
        }
        .frame(minWidth: 720, minHeight: 560)
        .onAppear {
            viewModel.refreshApps()
        }
    }
}
