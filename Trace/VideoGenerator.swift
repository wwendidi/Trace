import Foundation
import AVFoundation
import AppKit
import SwiftUI

class VideoGenerator: NSObject, NSSpeechSynthesizerDelegate {
    static let shared = VideoGenerator()
    
    // 全局复用这一个合成器
    private let synthesizer = NSSpeechSynthesizer()
    private var audioContinuation: CheckedContinuation<Void, Never>?
    
    override init() {
        super.init()
        synthesizer.delegate = self
    }
    
    // 主入口：生成视频
    func createTutorialVideo(tutorial: Tutorial, script: [String], completion: @escaping (URL?) -> Void) {
        let steps = tutorial.sortedSteps
        let count = min(steps.count, script.count)
        
        guard count > 0 else {
            print("❌ Empty step")
            completion(nil)
            return
        }
        
        Task {
            print("🎙️ Creating audio...")
            var audioAssets: [URL] = []
            var durations: [Double] = []
            
            // 1. 串行生成音频
            for i in 0..<count {
                let text = script[i]
                let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("trace_audio_\(i)_\(UUID().uuidString).aiff")
                
                // 生成音频文件
                await generateAudioSerial(text: text, to: fileURL)
                
                // 计算准确的“声画同步”时长
                let asset = AVURLAsset(url: fileURL)
                if let rawAudioDuration = try? await asset.load(.duration).seconds, rawAudioDuration > 0 {
                    
                    // 🔥 核心修复：
                    // 1. 基础时长 = 音频时长 + 1.0秒缓冲 (Wait 1s)
                    let targetDuration = rawAudioDuration + 1.0
                    
                    // 2. 帧率对齐：将时长向上取整到最近的帧 (30fps)
                    // 避免因为 Double 转 Int 造成的画面比声音短的“抢跑”现象
                    let fps: Double = 30.0
                    let frameCount = ceil(targetDuration * fps)
                    let alignedDuration = frameCount / fps
                    
                    audioAssets.append(fileURL)
                    durations.append(alignedDuration)
                    
                    print("✅ Step \(i): Audio \(String(format: "%.2f", rawAudioDuration))s -> Video Step \(String(format: "%.2f", alignedDuration))s")
                } else {
                    // Fallback
                    durations.append(4.0)
                }
            }
            
            // 2. 合成视频
            print("🎬 Making video...")
            await exportUsingAssetWriter(steps: Array(steps.prefix(count)), durations: durations, audioURLs: audioAssets, completion: completion)
        }
    }
    
    // 🎤 串行生成音频核心逻辑
    private func generateAudioSerial(text: String, to url: URL) async {
        return await withCheckedContinuation { continuation in
            self.audioContinuation = continuation
            synthesizer.startSpeaking(text, to: url)
        }
    }
    
    // 🎧 回调
    func speechSynthesizer(_ sender: NSSpeechSynthesizer, didFinishSpeaking finishedSpeaking: Bool) {
        audioContinuation?.resume()
        audioContinuation = nil
    }
    
    // 🎬 视频合成
    private func exportUsingAssetWriter(steps: [TraceStepModel], durations: [Double], audioURLs: [URL], completion: @escaping (URL?) -> Void) async {
        let width = 1920
        let height = 1080
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("Trace_Tutorial_\(UUID().uuidString).mp4")
        
        try? FileManager.default.removeItem(at: outputURL)
        
        guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4) else {
            completion(nil); return
        }
        
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: nil)
        
        if writer.canAdd(videoInput) { writer.add(videoInput) }
        
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        
        let mediaInputQueue = DispatchQueue(label: "mediaInputQueue")
        
        await withCheckedContinuation { continuation in
            videoInput.requestMediaDataWhenReady(on: mediaInputQueue) {
                var frameTime = CMTime.zero
                let fps: Int32 = 30
                
                for (index, step) in steps.enumerated() {
                    let nsImage = step.image ?? NSImage(size: NSSize(width: width, height: height))
                    guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
                    
                    // 获取对齐后的时长
                    let durationSeconds = durations.count > index ? durations[index] : 4.0
                    
                    // 这里的 frameCount 应该和 createTutorialVideo 里计算的一致
                    let frameCount = Int(round(durationSeconds * Double(fps)))
                    
                    for _ in 0..<frameCount {
                        while !videoInput.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.01) }
                        
                        if let buffer = self.pixelBufferFromImage(cgImage, size: CGSize(width: width, height: height)) {
                            adaptor.append(buffer, withPresentationTime: frameTime)
                        }
                        frameTime = CMTimeAdd(frameTime, CMTime(value: 1, timescale: fps))
                    }
                }
                
                videoInput.markAsFinished()
                writer.finishWriting {
                    continuation.resume()
                }
            }
        }
        
        if writer.status == .failed {
            print("❌ Video Writing Failed: \(String(describing: writer.error))")
            completion(nil)
            return
        }
        
        // 🎉 合并音频
        if audioURLs.isEmpty {
            completion(outputURL)
        } else {
            await muxAudio(videoURL: outputURL, audioURLs: audioURLs, durations: durations, finalCompletion: completion)
        }
    }
    
    // 🎧 合并音频轨道
    private func muxAudio(videoURL: URL, audioURLs: [URL], durations: [Double], finalCompletion: @escaping (URL?) -> Void) async {
        let mixComposition = AVMutableComposition()
        
        let videoAsset = AVURLAsset(url: videoURL)
        guard let videoTrack = try? await videoAsset.loadTracks(withMediaType: .video).first,
              let compositionVideoTrack = mixComposition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            finalCompletion(videoURL); return
        }
        
        let videoDuration = try? await videoAsset.load(.duration)
        try? compositionVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration ?? .zero), of: videoTrack, at: .zero)
        
        if let compositionAudioTrack = mixComposition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            var atTime = CMTime.zero
            
            for (index, audioURL) in audioURLs.enumerated() {
                guard FileManager.default.fileExists(atPath: audioURL.path) else { continue }
                
                let audioAsset = AVURLAsset(url: audioURL)
                if let track = try? await audioAsset.loadTracks(withMediaType: .audio).first {
                    let assetDuration = try? await audioAsset.load(.duration)
                    // 插入音频
                    try? compositionAudioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: assetDuration ?? .zero), of: track, at: atTime)
                }
                
                // 关键：将时间指针向后移动整个 Step 的时长（音频 + 1s）
                // 这样下一段音频就会在图片切换的同时开始播放
                let stepDuration = CMTime(seconds: durations[index], preferredTimescale: 600)
                atTime = CMTimeAdd(atTime, stepDuration)
            }
        }
        
        let finalURL = FileManager.default.temporaryDirectory.appendingPathComponent("Trace_Final_\(UUID().uuidString).mp4")
        guard let exportSession = AVAssetExportSession(asset: mixComposition, presetName: AVAssetExportPreset1920x1080) else {
            finalCompletion(videoURL); return
        }
        
        exportSession.outputURL = finalURL
        exportSession.outputFileType = .mp4
        await exportSession.export()
        
        if exportSession.status == .completed {
            print("✅ Video export success: \(finalURL)")
            finalCompletion(finalURL)
        } else {
            print("❌ Video export failed: \(String(describing: exportSession.error))")
            finalCompletion(videoURL)
        }
    }
    
    // 辅助：PixelBuffer
    private func pixelBufferFromImage(_ image: CGImage, size: CGSize) -> CVPixelBuffer? {
        var pxbuffer: CVPixelBuffer?
        let options: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height), kCVPixelFormatType_32ARGB, options as CFDictionary, &pxbuffer)
        guard let buffer = pxbuffer else { return nil }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        let pxdata = CVPixelBufferGetBaseAddress(buffer)
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: pxdata, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: rgbColorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
        
        context?.setFillColor(NSColor.black.cgColor)
        context?.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
        
        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)
        let aspect = imageWidth / imageHeight
        let targetAspect = size.width / size.height
        var drawRect = CGRect.zero
        
        if aspect > targetAspect {
            let newHeight = size.width / aspect
            drawRect = CGRect(x: 0, y: (size.height - newHeight) / 2, width: size.width, height: newHeight)
        } else {
            let newWidth = size.height * aspect
            drawRect = CGRect(x: (size.width - newWidth) / 2, y: 0, width: newWidth, height: size.height)
        }
        
        context?.draw(image, in: drawRect)
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }
}
