import SwiftUI

struct TraceTooltipView: View {
    @ObservedObject var manager: TraceManager
    let tutorial: Tutorial
    let stepNumber: Int
    let totalSteps: Int
    let instruction: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("STEP \(stepNumber) OF \(totalSteps)")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.8))
                    .cornerRadius(4)
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: { manager.hideTooltip() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.6))
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            
            Text(instruction)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
            
            HStack {
                Spacer()
                Button("Next") {
                    withAnimation {
                        manager.nextStep(for: tutorial)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.small)
            }
        }
        .padding()
        .frame(width: 240)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .gesture(
            DragGesture().onChanged { value in
                let currentFrame = manager.overlayPanel?.frame ?? .zero
                let newOrigin = CGPoint(
                    x: currentFrame.origin.x + value.translation.width,
                    y: currentFrame.origin.y - value.translation.height
                )
                manager.overlayPanel?.setFrameOrigin(newOrigin)
            }
        )
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
