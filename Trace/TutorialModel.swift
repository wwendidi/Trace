import Foundation
import SwiftData
import AppKit

@Model
final class Tutorial {
    var id: UUID
    var title: String
    var createdAt: Date
    
    @Relationship(deleteRule: .cascade, inverse: \TraceStepModel.tutorial)
    var steps: [TraceStepModel]?
    
    init(title: String = "新教程", steps: [TraceStepModel] = []) {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.steps = steps
    }
    
    // 用于 UI 排序
    var sortedSteps: [TraceStepModel] {
        (steps ?? []).sorted { $0.orderIndex < $1.orderIndex }
    }
}

@Model
final class TraceStepModel {
    var id: UUID
    var orderIndex: Int
    var frameString: String
    var instruction: String
    var detail: String
    var appName: String
    var elementName: String
    var imageData: Data?
    var tutorial: Tutorial?
    
    init(orderIndex: Int, frame: CGRect, instruction: String, detail: String = "", appName: String, elementName: String, image: NSImage?) {
        self.id = UUID()
        self.orderIndex = orderIndex
        self.frameString = NSStringFromRect(frame)
        self.instruction = instruction
        self.detail = detail
        self.appName = appName
        self.elementName = elementName
        
        if let tiff = image?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) {
            self.imageData = bitmap.representation(using: .png, properties: [:])
        }
    }
    
    var image: NSImage? {
        guard let data = imageData else { return nil }
        return NSImage(data: data)
    }
    
    var frame: CGRect {
        return NSRectFromString(frameString)
    }
}
