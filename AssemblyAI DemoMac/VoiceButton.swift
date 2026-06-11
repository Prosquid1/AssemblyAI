//
//  VoiceButton.swift
//  AssemblyAI DemoMac
//
//  Created by Oyeleke Okiki on 6/11/26.
//



import SwiftUI


struct VoiceButton: View {
    @Binding var isActive: Bool
    var onTap: () -> Void

    @State private var levels: [CGFloat] = Array(repeating: 0.2, count: 5)
    @State private var timer: Timer?

    var body: some View {
        Button(action: {
            onTap()
        }) {
            VStack(alignment: .center) {
                if (isActive) {
                    HStack(spacing: 2) {
                        ForEach(0..<levels.count, id: \.self) { i in
                            Capsule()
                                .fill(Color.white)
                                .frame(width: 2, height: 5 + levels[i] * 25)
                        }
                    }
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                }



            }.frame(width: 50, height: 50)
             .background(.red)
             .cornerRadius(25.0)
        }
        .buttonStyle(.plain)
        .onChange(of: isActive) { newValue in
            if newValue {
                startVoiceAnimation()
            } else {
                stopVoiceAnimation()
            }
        }
    }

    private func startVoiceAnimation() {
        stopVoiceAnimation()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                levels = levels.map { _ in CGFloat.random(in: 0...1) }
            }
        }
    }

    private func stopVoiceAnimation() {
        timer?.invalidate()
        timer = nil
        withAnimation(.easeOut(duration: 0.2)) {
            levels = Array(repeating: 0.2, count: 5)
        }
    }
}
