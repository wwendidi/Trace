import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Tutorial.createdAt, order: .reverse) private var tutorials: [Tutorial]
    @StateObject private var traceManager = TraceManager()
    @State private var selectedTutorial: Tutorial?
    @State private var zoomingImage: NSImage?

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTutorial) {
                ForEach(tutorials) { tutorial in
                    NavigationLink(value: tutorial) {
                        VStack(alignment: .leading) {
                            Text(tutorial.title).font(.headline)
                            Text("\(tutorial.steps?.count ?? 0) 步").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .contextMenu { Button(role: .destructive) { modelContext.delete(tutorial) } label: { Label("Delete tutorial", systemImage: "trash") } }
                }
            }
            .toolbar { Button(action: { traceManager.startRecording() }) { Label("New Recording", systemImage: "record.circle") } }
        } detail: {
            if !traceManager.recordedSteps.isEmpty || traceManager.isRecording {
                RecordingEditor(manager: traceManager)
            } else if let tutorial = selectedTutorial {
                TutorialDetailView(tutorial: tutorial, manager: traceManager, zoomingImage: $zoomingImage)
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "pencil.and.outline").font(.system(size: 50)).foregroundStyle(.gray)
                    Text("Select or start a new recording").foregroundStyle(.secondary)
                }
            }
        }
        .sheet(item: Binding(get: { zoomingImage.map { ZoomImage(image: $0) } }, set: { zoomingImage = $0?.image })) { z in ImageDetailView(image: z.image) }
    }
}

// MARK: - 录制编辑器 (正序)
struct RecordingEditor: View {
    @ObservedObject var manager: TraceManager
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Recording").font(.headline)
                Spacer()
                if manager.isRecording { Button("Stop Recording") { manager.stopRecording() }.buttonStyle(.borderedProminent).tint(.red) }
                Button("Save") { Task { await manager.saveTutorial(context: modelContext) } }.buttonStyle(.borderedProminent).tint(.orange)
            }.padding().background(Color(NSColor.windowBackgroundColor))
            
            List {
                InsertRow(index: -1, manager: manager)
                ForEach(Array(manager.recordedSteps.enumerated()), id: \.element.id) { index, step in
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            ImageBox(image: step.snapshot) { img in manager.updateRecordedStepImage(id: step.id, image: img) }
                            VStack(alignment: .leading) {
                                TextField("Title", text: Binding(get: { manager.recordedSteps[index].instruction }, set: { manager.recordedSteps[index].instruction = $0 }))
                                TextField("Description", text: Binding(get: { manager.recordedSteps[index].detail }, set: { manager.recordedSteps[index].detail = $0 }))
                            }
                            Button(action: { manager.recordedSteps.remove(at: index) }) { Image(systemName: "trash").foregroundColor(.red) }.buttonStyle(.plain)
                        }.padding().background(Color(NSColor.controlBackgroundColor).cornerRadius(12))
                        InsertRow(index: index, manager: manager)
                    }
                }
            }.listStyle(.sidebar)
        }
    }
}

// MARK: - 指南详情 (完整功能版)
struct TutorialDetailView: View {
    @Bindable var tutorial: Tutorial
    @ObservedObject var manager: TraceManager
    @Binding var zoomingImage: NSImage?
    @Environment(\.modelContext) private var modelContext
    @State private var isGeneratingVideo = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Tutorial Title", text: $tutorial.title).font(.largeTitle).bold().textFieldStyle(.plain)
                Spacer()
                
                // 导出 HTML
                Button(action: {
                    if let url = HTMLExporter.export(tutorial: tutorial) {
                        NSWorkspace.shared.open(url)
                    }
                }) { Label("Export HTML", systemImage: "square.and.arrow.up") }
                .buttonStyle(.bordered)
                
                // 生成 AI 视频
                Button(action: {
                    isGeneratingVideo = true
                    Task {
                        let steps = tutorial.sortedSteps
                        let apps = steps.map { $0.appName }
                        let actions = steps.map { $0.instruction }
                        
                        // 1. Gemini 生成脚本
                        let script = (try? await GeminiService().generateVideoScript(apps: apps, actions: actions)) ?? actions
                        
                        // 2. 合成视频
                        VideoGenerator.shared.createTutorialVideo(tutorial: tutorial, script: script) { url in
                            isGeneratingVideo = false
                            if let url = url { NSWorkspace.shared.open(url) }
                        }
                    }
                }) {
                    HStack {
                        if isGeneratingVideo { ProgressView().controlSize(.small) } else { Image(systemName: "sparkles") }
                        Text("AI Video")
                    }
                }
                .buttonStyle(.borderedProminent).tint(.purple).disabled(isGeneratingVideo)
                
                // 播放指南
                Button("Play interactive tutorial") { manager.playTutorial(tutorial) }.buttonStyle(.borderedProminent)
            }.padding()

            List {
                InsertRow(index: -1, manager: manager, targetTutorial: tutorial)
                
                // 使用 Array + Enumerated 修复 Binding 报错
                ForEach(Array(tutorial.sortedSteps.enumerated()), id: \.element.id) { index, step in
                    // 局部 Bindable
                    let bindableStep = Bindable(step)
                    
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            // 默认灰色占位符，点击才上传
                            ImageBox(image: step.image) { img in manager.updateStepImage(step: step, image: img) }
                                .onTapGesture(count: 2) { zoomingImage = step.image }
                            
                            VStack(alignment: .leading) {
                                TextField("Title", text: bindableStep.instruction).font(.headline).textFieldStyle(.plain)
                                TextField("Description", text: bindableStep.detail).font(.subheadline).foregroundStyle(.secondary).textFieldStyle(.plain)
                            }
                            Spacer()
                            Button(action: { manager.deleteStep(at: index, from: tutorial, context: modelContext) }) {
                                Image(systemName: "trash").foregroundColor(.red)
                            }.buttonStyle(.plain)
                        }
                        .padding().background(Color(NSColor.controlBackgroundColor).cornerRadius(12))
                        
                        InsertRow(index: index, manager: manager, targetTutorial: tutorial)
                    }
                }
            }.listStyle(.sidebar)
        }
    }
}

// MARK: - 通用组件
struct ImageBox: View {
    let image: NSImage?
    var onUpload: (NSImage) -> Void
    var body: some View {
        ZStack {
            if let img = image {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 8).fill(.gray.opacity(0.1))
                Image(systemName: "photo.badge.plus").foregroundColor(.gray)
            }
        }
        .frame(width: 100, height: 70).cornerRadius(8).clipped()
        .onTapGesture {
            let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]
            if panel.runModal() == .OK, let url = panel.url, let img = NSImage(contentsOf: url) { onUpload(img) }
        }
    }
}

struct InsertRow: View {
    let index: Int
    @ObservedObject var manager: TraceManager
    var targetTutorial: Tutorial? = nil
    @Environment(\.modelContext) private var modelContext
    var body: some View {
        HStack { Spacer(); Button(action: { manager.insertManualStep(after: index, into: targetTutorial, context: modelContext) }) {
            Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(.blue.gradient)
        }.buttonStyle(.plain); Spacer() }.padding(.vertical, 4)
    }
}

struct ImageDetailView: View {
    let image: NSImage
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack {
            HStack { Spacer(); Button("Close") { dismiss() }.keyboardShortcut(.escape, modifiers: []) }.padding()
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).padding()
        }.frame(minWidth: 800, minHeight: 600)
    }
}

struct ZoomImage: Identifiable { let id = UUID(); let image: NSImage }
