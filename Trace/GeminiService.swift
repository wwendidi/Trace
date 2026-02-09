import Foundation
import AppKit

class GeminiService {
    // ⚠️ 请确保这里填入了正确的 API Key
    private let apiKey = "YOUR_API_KEY_HERE"
    
    private let model = "gemini-2.0-flash-lite"
    
    // 🔥 新增：简单的请求队列锁
    private let queue = DispatchQueue(label: "com.trace.geminiQueue", qos: .userInitiated)
    private let semaphore = DispatchSemaphore(value: 1) // 信号量，控制并发
    
    // 1. 分析单张图片 (带限流)
    func analyzeElement(image: NSImage, appName: String) async throws -> String {
        // 🔥 强制等待：在发请求前，先看看信号量是否可用
        // 为了避免阻塞主线程，我们使用简单的 Task.sleep 模拟限流
        // 更好的方式是每次请求间隔 1~2 秒
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 强制休息 2 秒
        
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)") else { return "URL Error" }
        
        let resizedImage = resizeImage(image, to: CGSize(width: 1024, height: 1024))
        guard let tiff = resizedImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.6])
        else { return "Image Error" }
        
        let base64String = jpegData.base64EncodedString()
        
        let prompt = "This is a screenshot of '\(appName)'. The user clicked somewhere. Identify the UI element based on context. Return a VERY concise instruction (max 10 words) starting with a verb like 'Click', 'Select', 'Type'. Example: 'Click the Save button'."
        
        let body: [String: Any] = ["contents": [["parts": [["text": prompt], ["inline_data": ["mime_type": "image/jpeg", "data": base64String]]]]]]
        
        return try await sendRequest(url: url, body: body)
    }
    
    // 2. 生成视频脚本 (带限流)
    func generateVideoScript(apps: [String], actions: [String]) async throws -> [String] {
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 休息 1 秒
        
        let appList = Array(Set(apps)).joined(separator: ", ")
        let prompt = """
        You are a professional video tutorial creator.
        I have a tutorial with \(actions.count) steps using apps: \(appList).
        Here are the user actions:
        \(actions.enumerated().map { "\($0 + 1). \($1)" }.joined(separator: "\n"))
        Task: Convert these into a natural, spoken voiceover script. Return ONLY a raw JSON string array.
        """
        
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)") else { return [] }
        
        let body: [String: Any] = ["contents": [["parts": [["text": prompt]]]]]
        
        let responseString = try await sendRequest(url: url, body: body)
        
        let cleanJson = responseString
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            
        guard let data = cleanJson.data(using: .utf8),
              let scriptArray = try? JSONDecoder().decode([String].self, from: data) else {
            return actions
        }
        
        return scriptArray
    }

    // 3. 生成标题 (带限流)
    func generateTitle(apps: [String], elements: [String]) async throws -> String {
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 休息 1 秒
        
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)") else { return "New Tutorial" }
        
        let uniqueApps = Array(Set(apps)).joined(separator: ", ")
        let actionSummary = elements.prefix(5).joined(separator: ", ")
        
        let prompt = "Generate a short title (under 6 words) for a tutorial using \(uniqueApps). Actions: \(actionSummary). Return ONLY the title."
        
        let body: [String: Any] = ["contents": [["parts": [["text": prompt]]]]]
        return try await sendRequest(url: url, body: body)
    }
    
    private func resizeImage(_ image: NSImage, to maxSize: CGSize) -> NSImage {
        let originalSize = image.size
        let aspectRatio = originalSize.width / originalSize.height
        var newSize = originalSize
        
        if originalSize.width > maxSize.width || originalSize.height > maxSize.height {
            if aspectRatio > 1 {
                newSize = CGSize(width: maxSize.width, height: maxSize.width / aspectRatio)
            } else {
                newSize = CGSize(width: maxSize.height * aspectRatio, height: maxSize.height)
            }
        } else {
            return image
        }
        
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize), from: NSRect(origin: .zero, size: originalSize), operation: .copy, fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
    
    // 发送请求核心 (增加 429 重试机制)
    private func sendRequest(url: URL, body: [String: Any], retryCount: Int = 0) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // 🔥 自动重试机制
        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 429 {
                if retryCount < 3 {
                    print("⚠️ Rate Limited (429). Retrying in 3 seconds... (Attempt \(retryCount + 1))")
                    try? await Task.sleep(nanoseconds: 3_000_000_000) // 等待 3 秒再重试
                    return try await sendRequest(url: url, body: body, retryCount: retryCount + 1)
                } else {
                    return "Error: Too many requests. Please wait."
                }
            }
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
                return "API Error: \(message)"
            }
            if let candidates = json["candidates"] as? [[String: Any]],
               let content = candidates.first?["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]],
               let text = parts.first?["text"] as? String {
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return "Error"
    }
}
