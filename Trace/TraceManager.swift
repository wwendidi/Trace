import SwiftUI
import AppKit
import ScreenCaptureKit
import SwiftData
import Combine

struct TraceStep: Identifiable, Equatable {
    let id: UUID
    var frame: CGRect
    var instruction: String
    var detail: String = ""
    var appName: String
    var elementName: String
    var snapshot: NSImage?
    
    static func == (lhs: TraceStep, rhs: TraceStep) -> Bool { lhs.id == rhs.id }
}

class TraceManager: ObservableObject {
    @Published var isRecording = false
    @Published var recordedSteps: [TraceStep] = []
    @Published var currentPlayIndex = 0
    
    private let geminiService = GeminiService()
    private var clickMonitor: Any?
    var recordingIndicatorPanel: NSPanel?
    var overlayPanel: TraceOverlayPanel?

    // MARK: - 录制逻辑
    func startRecording() {
        isRecording = true
        showRecordingIndicator()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            DispatchQueue.main.async { self?.captureClick() }
        }
    }
    
    func stopRecording() {
        isRecording = false
        recordingIndicatorPanel?.orderOut(nil)
        if let monitor = clickMonitor { NSEvent.removeMonitor(monitor); clickMonitor = nil }
    }

    private func captureClick() {
        guard isRecording else { return }
        let currentApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "App"
        let mousePos = NSEvent.mouseLocation
        let screenHeight = NSScreen.main?.frame.height ?? 0
        let (elementFrame, fallbackName) = findElementInfoUnderMouse() ?? (CGRect(x: mousePos.x-40, y: mousePos.y-40, width: 80, height: 80), "区域")
        
        let newStep = TraceStep(id: UUID(), frame: elementFrame, instruction: "🤖 AI Analyzing...", appName: currentApp, elementName: fallbackName)
        recordedSteps.append(newStep)
        let targetID = newStep.id

        Task(priority: .userInitiated) {
            let cropRect = CGRect(x: mousePos.x - 150, y: screenHeight - mousePos.y - 150, width: 300, height: 300)
            let image = await captureScreen(at: cropRect)
            
            await MainActor.run {
                if let idx = self.recordedSteps.firstIndex(where: { $0.id == targetID }) { self.recordedSteps[idx].snapshot = image }
            }
            
            if let img = image {
                let aiInstruction = (try? await geminiService.analyzeElement(image: img, appName: currentApp)) ?? "点击 \(fallbackName)"
                await MainActor.run {
                    if let idx = self.recordedSteps.firstIndex(where: { $0.id == targetID }) { self.recordedSteps[idx].instruction = aiInstruction }
                }
            }
        }
    }

    // MARK: - 插入与更新
    func insertManualStep(after index: Int, into tutorial: Tutorial? = nil, context: ModelContext? = nil) {
        let defaultInstruction = "Manual add steps"
        if let tutorial = tutorial, let context = context {
            let sorted = tutorial.sortedSteps
            for i in (index + 1)..<sorted.count { sorted[i].orderIndex += 1 }
            let newStep = TraceStepModel(orderIndex: index + 1, frame: .zero, instruction: defaultInstruction, appName: "Manual", elementName: "Manual", image: nil)
            newStep.tutorial = tutorial
            context.insert(newStep)
        } else {
            let manualStep = TraceStep(id: UUID(), frame: .zero, instruction: defaultInstruction, appName: "Manual", elementName: "Manual", snapshot: nil)
            let insertIndex = min(index + 1, recordedSteps.count)
            recordedSteps.insert(manualStep, at: insertIndex)
        }
    }
    
    func updateStepImage(step: TraceStepModel, image: NSImage) {
        step.imageData = image.tiffRepresentation
        step.instruction = "🤖 AI analyzing..."
        Task(priority: .background) {
            let aiText = (try? await geminiService.analyzeElement(image: image, appName: "Uploaded Image")) ?? "Manual Step"
            await MainActor.run { step.instruction = aiText }
        }
    }
    
    func updateRecordedStepImage(id: UUID, image: NSImage) {
        if let idx = recordedSteps.firstIndex(where: { $0.id == id }) {
            recordedSteps[idx].snapshot = image
            recordedSteps[idx].instruction = "🤖 AI analyzing..."
            Task(priority: .background) {
                let aiText = (try? await geminiService.analyzeElement(image: image, appName: "Uploaded Image")) ?? "Manual Step"
                await MainActor.run { self.recordedSteps[idx].instruction = aiText }
            }
        }
    }
    
    func deleteStep(at index: Int, from tutorial: Tutorial? = nil, context: ModelContext? = nil) {
        if let tutorial = tutorial, let context = context {
            let steps = tutorial.sortedSteps
            guard index < steps.count else { return }
            context.delete(steps[index])
            let remaining = tutorial.sortedSteps.filter { $0.id != steps[index].id }
            for (newIdx, s) in remaining.enumerated() { s.orderIndex = newIdx }
            try? context.save()
        } else {
            recordedSteps.remove(at: index)
        }
    }

    @MainActor
    func saveTutorial(context: ModelContext) async {
        guard !recordedSteps.isEmpty else { return }
        let stepsToSave = recordedSteps
        let title = (try? await geminiService.generateTitle(apps: stepsToSave.map{$0.appName}, elements: stepsToSave.map{$0.elementName})) ?? "New Tutorial"
        
        let processedSteps: [(TraceStep, Data?)] = await Task.detached(priority: .userInitiated) {
            return stepsToSave.map { step in
                var data: Data? = nil
                if let image = step.snapshot, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) {
                    data = bitmap.representation(using: .png, properties: [:])
                }
                return (step, data)
            }
        }.value
        
        let newTutorial = Tutorial(title: title)
        context.insert(newTutorial)
        
        for (idx, (step, data)) in processedSteps.enumerated() {
            let stepModel = TraceStepModel(orderIndex: idx, frame: step.frame, instruction: step.instruction, detail: step.detail, appName: step.appName, elementName: step.elementName, image: nil)
            stepModel.imageData = data
            stepModel.tutorial = newTutorial
        }
        try? context.save()
        print("✅ Tutorial saved successfully")
        recordedSteps.removeAll()
        stopRecording()
    }

    // MARK: - Play logic
    func playTutorial(_ tutorial: Tutorial) {
        let steps = tutorial.sortedSteps
        guard !steps.isEmpty else { return }
        currentPlayIndex = 0
        showTooltip(for: steps[0], in: tutorial)
    }

    func nextStep(for tutorial: Tutorial) {
        let steps = tutorial.sortedSteps
        if currentPlayIndex < steps.count - 1 {
            currentPlayIndex += 1
            showTooltip(for: steps[currentPlayIndex], in: tutorial)
        } else {
            hideTooltip()
        }
    }

    func hideTooltip() { overlayPanel?.orderOut(nil) }

    private func showTooltip(for step: TraceStepModel, in tutorial: Tutorial) {
        // 1. 获取屏幕尺寸
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        
        var tooltipRect: NSRect
        let width: CGFloat = 240
        let height: CGFloat = 150
        
        // 2. 检查坐标是否有效 (是否是手动步骤或 0 坐标)
        if step.frame == .zero || step.frame.width == 0 {
            // 🔥 情况 A: 无效坐标 -> 显示在屏幕正中央
            let centerX = screenFrame.midX - (width / 2)
            let centerY = screenFrame.midY - (height / 2)
            tooltipRect = NSRect(x: centerX, y: centerY, width: width, height: height)
        } else {
            // 🔥 情况 B: 有效坐标 -> 显示在元素下方
            let stepFrame = step.frame
            // 默认位置：元素下方居中
            var x = stepFrame.midX - (width / 2)
            var y = stepFrame.minY - height - 10 // 往下偏移 10px
            
            // 3. 边界检查 (防止飞出屏幕)
            // 如果太靠左，靠左对齐
            if x < screenFrame.minX { x = screenFrame.minX + 10 }
            // 如果太靠右，靠右对齐
            if x + width > screenFrame.maxX { x = screenFrame.maxX - width - 10 }
            // 如果太靠下（被底部遮挡），改为显示在元素上方
            if y < screenFrame.minY {
                y = stepFrame.maxY + 10
            }
            
            tooltipRect = NSRect(x: x, y: y, width: width, height: height)
        }
        
        // 4. 创建或更新窗口
        if overlayPanel == nil {
            overlayPanel = TraceOverlayPanel(contentRect: tooltipRect)
        }
        
        let totalSteps = tutorial.steps?.count ?? 0
        let tooltipView = TraceTooltipView(
            manager: self,
            tutorial: tutorial,
            stepNumber: currentPlayIndex + 1,
            totalSteps: totalSteps,
            instruction: step.instruction
        )
        
        overlayPanel?.contentView = NSHostingView(rootView: tooltipView)
        overlayPanel?.setFrame(tooltipRect, display: true)
        
        // 🔥 强制前置显示，解决点击无反应问题
        overlayPanel?.makeKeyAndOrderFront(nil)
    }

    // MARK: - 辅助
    @MainActor private func captureScreen(at rect: CGRect) async -> NSImage? {
        do {
            let content = try await SCShareableContent.current
            guard let display = content.displays.first else { return nil }
            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.sourceRect = rect; config.width = Int(rect.width); config.height = Int(rect.height)
            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return NSImage(cgImage: cgImage, size: rect.size)
        } catch { return nil }
    }
    
    private func showRecordingIndicator() {
        if recordingIndicatorPanel == nil {
            let screen = NSScreen.main?.frame ?? .zero
            let panel = NSPanel(contentRect: CGRect(x: screen.width - 160, y: screen.height - 80, width: 140, height: 36), styleMask: [.borderless], backing: .buffered, defer: false)
            panel.isFloatingPanel = true; panel.level = .screenSaver; panel.backgroundColor = .clear
            panel.contentView = NSHostingView(rootView: HStack { Circle().fill(Color.red).frame(width: 8); Text("Recording...").bold().foregroundColor(.white) }.padding(8).background(Color.black.opacity(0.8)).cornerRadius(18))
            recordingIndicatorPanel = panel
        }
        recordingIndicatorPanel?.orderFront(nil)
    }

    private func findElementInfoUnderMouse() -> (CGRect, String)? {
        let pos = NSEvent.mouseLocation; let h = NSScreen.main?.frame.height ?? 0; let point = CGPoint(x: pos.x, y: h - pos.y)
        var el: AXUIElement?; if AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &el) == .success, let f = el {
            var p = CGPoint.zero; var s = CGSize.zero; var t: CFTypeRef?
            AXValueGetValue(try! getAXValue(f, "AXPosition"), .cgPoint, &p)
            AXValueGetValue(try! getAXValue(f, "AXSize"), .cgSize, &s)
            AXUIElementCopyAttributeValue(f, "AXTitle" as CFString, &t)
            return (CGRect(x: p.x, y: h - p.y - s.height, width: s.width, height: s.height), (t as? String) ?? "元素")
        }
        return nil
    }
    private func getAXValue(_ e: AXUIElement, _ a: String) throws -> AXValue { var v: CFTypeRef?; AXUIElementCopyAttributeValue(e, a as CFString, &v); return v as! AXValue }
}
