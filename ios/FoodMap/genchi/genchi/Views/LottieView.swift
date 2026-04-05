import SwiftUI

#if canImport(Lottie)
import Lottie
#endif

enum FanTuanAnimationPlayback: Equatable {
    case loop
    case playOnce
}

enum FanTuanAnimationAsset: String, CaseIterable {
    case idle = "fantuan_idle"
    case hungry = "fantuan_hungry"
    case sleepy = "fantuan_sleepy"
    case excited = "fantuan_excited"
    case rainy = "fantuan_rainy"
    case eating = "fantuan_eating"
    case happy = "fantuan_happy"
    case starving = "fantuan_starving"
    case tap = "fantuan_tap"

    var duration: Double {
        switch self {
        case .idle, .sleepy, .rainy, .starving:
            return 3.0
        case .hungry:
            return 2.5
        case .excited:
            return 2.0
        case .eating, .happy:
            return 1.5
        case .tap:
            return 0.8
        }
    }
}

struct FanTuanAnimationDescriptor: Equatable {
    let asset: FanTuanAnimationAsset
    let playback: FanTuanAnimationPlayback

    var name: String { asset.rawValue }
    var duration: Double { asset.duration }

    static func looping(_ asset: FanTuanAnimationAsset) -> Self {
        Self(asset: asset, playback: .loop)
    }

    static func oneShot(_ asset: FanTuanAnimationAsset) -> Self {
        Self(asset: asset, playback: .playOnce)
    }
}

struct LottieView: View {
    let animation: FanTuanAnimationDescriptor
    var playbackID: Int = 0

    var body: some View {
        Group {
#if canImport(Lottie)
            NativeLottieView(animation: animation, playbackID: playbackID)
#else
            FanTuanAnimatedFallbackView(animation: animation, playbackID: playbackID)
#endif
        }
        .accessibilityLabel("饭团动画")
    }
}

struct FanTuanStickerView: View {
    var asset: FanTuanAnimationAsset = .idle

    var body: some View {
        FanTuanCharacterScene(asset: asset, progress: 0.16)
            .aspectRatio(1, contentMode: .fit)
            .accessibilityHidden(true)
    }
}

#if canImport(Lottie)
private struct NativeLottieView: UIViewRepresentable {
    let animation: FanTuanAnimationDescriptor
    let playbackID: Int

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.clipsToBounds = true

        let animationView = context.coordinator.animationView
        animationView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(animationView)

        NSLayoutConstraint.activate([
            animationView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            animationView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            animationView.topAnchor.constraint(equalTo: container.topAnchor),
            animationView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let animationView = context.coordinator.animationView

        if context.coordinator.lastName != animation.name {
            animationView.animation = LottieAnimation.named(animation.name, bundle: .main)
            context.coordinator.lastName = animation.name
        }

        animationView.loopMode = animation.playback == .loop ? .loop : .playOnce

        if context.coordinator.lastPlaybackID != playbackID || context.coordinator.lastPlayback != animation.playback {
            context.coordinator.lastPlaybackID = playbackID
            context.coordinator.lastPlayback = animation.playback
            animationView.stop()
            animationView.currentProgress = 0
            animationView.play()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIView, context: Context) -> CGSize? {
        let width = proposal.width ?? proposal.height ?? 1
        let height = proposal.height ?? proposal.width ?? 1
        return CGSize(width: width, height: height)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        let animationView: LottieAnimationView = {
            let view = LottieAnimationView()
            view.backgroundBehavior = .pauseAndRestore
            view.contentMode = .scaleAspectFit
            view.clipsToBounds = true
            view.layer.masksToBounds = true
            view.shouldRasterizeWhenIdle = false
            return view
        }()

        var lastName: String?
        var lastPlaybackID = -1
        var lastPlayback: FanTuanAnimationPlayback?
    }
}
#endif

private struct FanTuanAnimatedFallbackView: View {
    let animation: FanTuanAnimationDescriptor
    let playbackID: Int

    @State private var startedAt = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            FanTuanCharacterScene(
                asset: animation.asset,
                progress: progress(at: timeline.date)
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear {
            startedAt = Date()
        }
        .onChange(of: playbackID) { _, _ in
            startedAt = Date()
        }
        .onChange(of: animation.name) { _, _ in
            startedAt = Date()
        }
    }

    private func progress(at date: Date) -> Double {
        let elapsed = max(0, date.timeIntervalSince(startedAt))
        if animation.playback == .loop {
            let remainder = elapsed.truncatingRemainder(dividingBy: animation.duration)
            return remainder / animation.duration
        }
        return min(1, elapsed / animation.duration)
    }
}

private struct FanTuanCharacterScene: View {
    let asset: FanTuanAnimationAsset
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let metrics = FanTuanMetrics(size: size)

            ZStack {
                if asset == .excited || asset == .hungry || asset == .happy {
                    sparkleOverlay(metrics: metrics)
                }

                if asset == .rainy {
                    umbrellaOverlay(metrics: metrics)
                    rainOverlay(metrics: metrics)
                }

                if asset == .sleepy {
                    sleepyBubbleOverlay(metrics: metrics)
                }

                if asset == .tap {
                    questionBubbleOverlay(metrics: metrics)
                }

                characterCore(metrics: metrics)

                if asset == .starving {
                    sweatOverlay(metrics: metrics)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private func characterCore(metrics: FanTuanMetrics) -> some View {
        let motion = motion(for: metrics)
        let cheekOpacity = blushOpacity
        let eyeBlink = blinkScale
        let droolOpacity = droolAlpha

        return ZStack {
            Ellipse()
                .fill(Color.black.opacity(0.08))
                .frame(width: metrics.shadowWidth, height: metrics.shadowHeight)
                .blur(radius: metrics.size * 0.015)
                .offset(y: metrics.size * 0.31)
                .scaleEffect(x: 1 - abs(motion.y) * 0.003, y: 1, anchor: .center)

            ZStack {
                feet(metrics: metrics)
                    .offset(y: metrics.size * 0.18)

                OnigiriShape()
                    .fill(Color(red: 1.0, green: 0.985, blue: 0.95))

                riceGrains(metrics: metrics)

                OnigiriShape()
                    .fill(Color.white.opacity(0.66))
                    .scaleEffect(x: 0.44, y: 0.22, anchor: .topLeading)
                    .offset(x: -metrics.size * 0.1, y: -metrics.size * 0.12)
                    .blur(radius: metrics.size * 0.005)

                belt(metrics: metrics)
                    .offset(y: metrics.size * 0.11)

                bib(metrics: metrics)
                    .offset(y: metrics.size * 0.22)

                cheeks(metrics: metrics, opacity: cheekOpacity)
                eyes(metrics: metrics, blinkScale: eyeBlink)
                mouth(metrics: metrics)

                if droolOpacity > 0 {
                    RoundedRectangle(cornerRadius: metrics.size * 0.022, style: .continuous)
                        .fill(Color(red: 0.58, green: 0.84, blue: 0.99).opacity(droolOpacity))
                        .frame(width: metrics.size * 0.05, height: metrics.size * 0.14)
                        .offset(y: metrics.size * 0.22)
                }

                OnigiriShape()
                    .stroke(Color.black, lineWidth: metrics.outlineWidth)
            }
            .frame(width: metrics.bodyWidth, height: metrics.bodyHeight)
            .offset(x: motion.x, y: motion.y)
            .rotationEffect(.degrees(motion.rotation))
            .scaleEffect(x: motion.scaleX, y: motion.scaleY, anchor: .center)
        }
    }

    private func riceGrains(metrics: FanTuanMetrics) -> some View {
        ZStack {
            ForEach(Array(grainLayout.enumerated()), id: \.offset) { _, grain in
                RiceGrainShape()
                    .fill(Color(red: 0.96, green: 0.91, blue: 0.8))
                    .frame(width: metrics.size * grain.width, height: metrics.size * grain.height)
                    .rotationEffect(.degrees(grain.rotation))
                    .offset(x: metrics.size * grain.x, y: metrics.size * grain.y)
                    .opacity(grain.opacity)
            }
        }
    }

    private func feet(metrics: FanTuanMetrics) -> some View {
        HStack(spacing: metrics.size * 0.46) {
            Ellipse()
                .fill(Color.black)
                .frame(width: metrics.footWidth, height: metrics.footHeight)
                .rotationEffect(.degrees(16))

            Ellipse()
                .fill(Color.black)
                .frame(width: metrics.footWidth, height: metrics.footHeight)
                .rotationEffect(.degrees(-16))
        }
    }

    private func belt(metrics: FanTuanMetrics) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: metrics.beltRadius, style: .continuous)
                .fill(Color(red: 0.34, green: 0.67, blue: 0.71))
                .overlay(
                    RoundedRectangle(cornerRadius: metrics.beltRadius, style: .continuous)
                        .stroke(Color.black, lineWidth: metrics.outlineWidth * 0.72)
                )
                .frame(width: metrics.beltWidth, height: metrics.beltHeight)

            HStack(spacing: metrics.size * 0.015) {
                ForEach(0..<4, id: \.self) { index in
                    CloudMotifShape()
                        .stroke(Color(red: 0.95, green: 0.82, blue: 0.52), lineWidth: metrics.outlineWidth * 0.4)
                        .frame(width: metrics.size * (index == 1 || index == 2 ? 0.16 : 0.13), height: metrics.size * 0.06)
                }
            }
            .offset(y: metrics.size * 0.002)
        }
    }

    private func bib(metrics: FanTuanMetrics) -> some View {
        ZStack {
            BibShape()
                .fill(Color(red: 1.0, green: 0.96, blue: 0.84))
                .overlay(
                    BibShape()
                        .stroke(Color.black, lineWidth: metrics.outlineWidth * 0.7)
                )
                .frame(width: metrics.bibWidth, height: metrics.bibHeight)

            ZStack {
                ForEach(Array(flowerLayout.enumerated()), id: \.offset) { _, flower in
                    flowerView(metrics: metrics, color: flower.color)
                        .frame(width: metrics.size * flower.size, height: metrics.size * flower.size)
                        .offset(x: metrics.size * flower.x, y: metrics.size * flower.y)
                }

                RoundMedallionShape()
                    .stroke(Color(red: 0.85, green: 0.43, blue: 0.28), lineWidth: metrics.outlineWidth * 0.45)
                    .frame(width: metrics.size * 0.16, height: metrics.size * 0.16)

                RoundMedallionShape()
                    .trim(from: 0.08, to: 0.42)
                    .stroke(Color(red: 0.85, green: 0.43, blue: 0.28), style: StrokeStyle(lineWidth: metrics.outlineWidth * 0.38, lineCap: .round))
                    .frame(width: metrics.size * 0.11, height: metrics.size * 0.11)

                RoundMedallionShape()
                    .trim(from: 0.58, to: 0.92)
                    .stroke(Color(red: 0.85, green: 0.43, blue: 0.28), style: StrokeStyle(lineWidth: metrics.outlineWidth * 0.38, lineCap: .round))
                    .frame(width: metrics.size * 0.11, height: metrics.size * 0.11)
                    .rotationEffect(.degrees(180))
            }
        }
    }

    @ViewBuilder
    private func cheeks(metrics: FanTuanMetrics, opacity: Double) -> some View {
        let color = Color(red: 0.98, green: 0.72, blue: 0.8).opacity(opacity)

        HStack(spacing: metrics.eyeSpacing * 0.96) {
            blushMark(metrics: metrics, color: color)
            blushMark(metrics: metrics, color: color)
        }
        .offset(y: metrics.size * 0.13)
    }

    @ViewBuilder
    private func eyes(metrics: FanTuanMetrics, blinkScale: CGFloat) -> some View {
        switch eyeStyle {
        case .dot:
            HStack(spacing: metrics.eyeSpacing) {
                eyeDot(metrics: metrics)
                eyeDot(metrics: metrics)
            }
            .scaleEffect(x: 1, y: blinkScale, anchor: .center)
            .offset(y: metrics.size * -0.02)
        case .sleepy:
            HStack(spacing: metrics.eyeSpacing) {
                eyeLine(metrics: metrics, angle: -10)
                eyeLine(metrics: metrics, angle: 10)
            }
            .offset(y: metrics.size * -0.02)
        case .happy:
            HStack(spacing: metrics.eyeSpacing) {
                eyeLine(metrics: metrics, angle: 18)
                eyeLine(metrics: metrics, angle: -18)
            }
            .offset(y: metrics.size * -0.04)
        case .wink:
            HStack(spacing: metrics.eyeSpacing) {
                eyeLine(metrics: metrics, angle: -10)
                eyeDot(metrics: metrics)
            }
            .offset(y: metrics.size * -0.02)
        case .cross:
            HStack(spacing: metrics.eyeSpacing) {
                eyeCross(metrics: metrics)
                eyeCross(metrics: metrics)
            }
            .offset(y: metrics.size * -0.02)
        }
    }

    @ViewBuilder
    private func mouth(metrics: FanTuanMetrics) -> some View {
        switch mouthStyle {
        case .smile:
            Capsule(style: .continuous)
                .fill(Color(red: 0.549, green: 0.298, blue: 0.298))
                .frame(width: metrics.mouthWidth * 0.9, height: metrics.mouthHeight * 0.55)
                .offset(y: metrics.size * 0.15)
        case .open:
            Circle()
                .fill(Color(red: 0.549, green: 0.298, blue: 0.298))
                .frame(width: metrics.mouthWidth * (1 + chewPulse * 0.18), height: metrics.mouthHeight * (1 + chewPulse * 0.24))
                .offset(y: metrics.size * 0.15)
        case .smallO:
            Circle()
                .fill(Color(red: 0.549, green: 0.298, blue: 0.298))
                .frame(width: metrics.mouthWidth * 0.75, height: metrics.mouthHeight * 0.86)
                .offset(y: metrics.size * 0.15)
        case .flat:
            Capsule(style: .continuous)
                .fill(Color(red: 0.549, green: 0.298, blue: 0.298))
                .frame(width: metrics.mouthWidth * 0.9, height: metrics.mouthHeight * 0.35)
                .offset(y: metrics.size * 0.15)
        }
    }

    @ViewBuilder
    private func sparkleOverlay(metrics: FanTuanMetrics) -> some View {
        let pulse: CGFloat = 0.7 + sparklePulse * 0.45
        let leftOpacity = asset == .happy ? 0.55 : 0.8
        let rightOpacity = asset == .happy ? 0.4 : 0.65

        ZStack {
            sparkle(size: metrics.size * 0.11, color: asset == .happy ? Color(red: 1, green: 0.72, blue: 0.8) : Color(red: 1, green: 0.78, blue: 0.3))
                .scaleEffect(pulse)
                .opacity(leftOpacity)
                .offset(x: -metrics.size * 0.28, y: -metrics.size * 0.16)

            sparkle(size: metrics.size * 0.1, color: asset == .happy ? Color(red: 1, green: 0.84, blue: 0.91) : Color(red: 1, green: 0.91, blue: 0.58))
                .scaleEffect(CGFloat(1.15) - sparklePulse * 0.2)
                .opacity(rightOpacity)
                .offset(x: metrics.size * 0.28, y: -metrics.size * 0.18)

            if asset == .excited {
                sparkle(size: metrics.size * 0.13, color: Color(red: 1, green: 0.88, blue: 0.54))
                    .scaleEffect(CGFloat(0.75) + sparklePulse * 0.5)
                    .opacity(0.82)
                    .offset(y: -metrics.size * 0.34)
            }
        }
    }

    @ViewBuilder
    private func umbrellaOverlay(metrics: FanTuanMetrics) -> some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(Color(red: 0.4, green: 0.68, blue: 0.91))
                .frame(width: metrics.size * 0.42, height: metrics.size * 0.18)
                .offset(y: -metrics.size * 0.34)

            RoundedRectangle(cornerRadius: metrics.size * 0.016, style: .continuous)
                .fill(Color(red: 0.55, green: 0.35, blue: 0.17))
                .frame(width: metrics.size * 0.026, height: metrics.size * 0.18)
                .offset(y: -metrics.size * 0.22)

            Circle()
                .trim(from: 0.08, to: 0.68)
                .stroke(Color(red: 0.55, green: 0.35, blue: 0.17), lineWidth: metrics.size * 0.015)
                .frame(width: metrics.size * 0.09, height: metrics.size * 0.09)
                .rotationEffect(.degrees(90))
                .offset(x: metrics.size * 0.035, y: -metrics.size * 0.135)
        }
        .offset(x: motion(for: metrics).x * 0.2)
    }

    @ViewBuilder
    private func rainOverlay(metrics: FanTuanMetrics) -> some View {
        let drift = CGFloat(sin(progress * .pi * 4)) * metrics.size * 0.02

        ZStack {
            rainDrop(size: metrics.size * 0.09)
                .opacity(0.75)
                .offset(x: -metrics.size * 0.3, y: -metrics.size * 0.15 + drift)

            rainDrop(size: metrics.size * 0.08)
                .opacity(0.55)
                .offset(x: metrics.size * 0.29, y: -metrics.size * 0.12 - drift)
        }
    }

    @ViewBuilder
    private func sleepyBubbleOverlay(metrics: FanTuanMetrics) -> some View {
        let yLift = CGFloat(sin(progress * .pi * 2)) * metrics.size * 0.03

        ZStack {
            Circle()
                .fill(Color(red: 0.78, green: 0.84, blue: 1).opacity(0.76))
                .frame(width: metrics.size * 0.11, height: metrics.size * 0.11)
                .offset(x: metrics.size * 0.18, y: -metrics.size * 0.33 + yLift)

            Circle()
                .fill(Color(red: 0.84, green: 0.89, blue: 1).opacity(0.58))
                .frame(width: metrics.size * 0.07, height: metrics.size * 0.07)
                .offset(x: metrics.size * 0.31, y: -metrics.size * 0.46 + yLift * 1.3)
        }
    }

    @ViewBuilder
    private func sweatOverlay(metrics: FanTuanMetrics) -> some View {
        let y = CGFloat(sin(progress * .pi * 4)) * metrics.size * 0.03

        Circle()
            .fill(Color(red: 0.56, green: 0.83, blue: 1).opacity(0.9))
            .frame(width: metrics.size * 0.075, height: metrics.size * 0.11)
            .rotationEffect(.degrees(20))
            .offset(x: metrics.size * 0.22, y: -metrics.size * 0.1 + y)
    }

    @ViewBuilder
    private func questionBubbleOverlay(metrics: FanTuanMetrics) -> some View {
        let bubbleScale = questionScale
        let opacity = questionOpacity

        ZStack {
            Circle()
                .fill(Color.white.opacity(opacity))
                .frame(width: metrics.size * 0.2, height: metrics.size * 0.2)

            RoundedRectangle(cornerRadius: metrics.size * 0.012, style: .continuous)
                .fill(Color.white.opacity(opacity))
                .frame(width: metrics.size * 0.035, height: metrics.size * 0.035)
                .rotationEffect(.degrees(36))
                .offset(x: -metrics.size * 0.035, y: metrics.size * 0.09)

            HStack(spacing: metrics.size * 0.016) {
                Circle().fill(Color.orange.opacity(opacity)).frame(width: metrics.size * 0.026, height: metrics.size * 0.026)
                Circle().fill(Color.orange.opacity(opacity)).frame(width: metrics.size * 0.026, height: metrics.size * 0.026)
                Circle().fill(Color.orange.opacity(opacity)).frame(width: metrics.size * 0.026, height: metrics.size * 0.026)
            }
        }
        .scaleEffect(bubbleScale)
        .offset(x: metrics.size * 0.28, y: -metrics.size * 0.28)
    }

    private func eyeDot(metrics: FanTuanMetrics) -> some View {
        ZStack(alignment: .topLeading) {
            Circle()
                .fill(Color.black)
                .frame(width: metrics.eyeWidth, height: metrics.eyeHeight)

            Circle()
                .fill(Color.white)
                .frame(width: metrics.eyeWidth * 0.26, height: metrics.eyeWidth * 0.26)
                .offset(x: metrics.eyeWidth * 0.16, y: metrics.eyeHeight * 0.14)
        }
    }

    private func eyeLine(metrics: FanTuanMetrics, angle: Double) -> some View {
        RoundedRectangle(cornerRadius: metrics.eyeWidth * 0.25, style: .continuous)
            .fill(Color.black)
            .frame(width: metrics.eyeWidth * 1.4, height: metrics.eyeHeight * 0.35)
            .rotationEffect(.degrees(angle))
    }

    private func eyeCross(metrics: FanTuanMetrics) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: metrics.eyeWidth * 0.15, style: .continuous)
                .fill(Color.black)
                .frame(width: metrics.eyeWidth * 1.35, height: metrics.eyeHeight * 0.28)
                .rotationEffect(.degrees(40))

            RoundedRectangle(cornerRadius: metrics.eyeWidth * 0.15, style: .continuous)
                .fill(Color.black)
                .frame(width: metrics.eyeWidth * 1.35, height: metrics.eyeHeight * 0.28)
                .rotationEffect(.degrees(-40))
        }
    }

    private func blushMark(metrics: FanTuanMetrics, color: Color) -> some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: metrics.cheekWidth, height: metrics.cheekHeight)

            HStack(spacing: metrics.size * 0.013) {
                Capsule(style: .continuous)
                    .fill(Color(red: 0.94, green: 0.45, blue: 0.58).opacity(0.85))
                    .frame(width: metrics.size * 0.012, height: metrics.size * 0.05)
                    .rotationEffect(.degrees(18))

                Capsule(style: .continuous)
                    .fill(Color(red: 0.94, green: 0.45, blue: 0.58).opacity(0.85))
                    .frame(width: metrics.size * 0.012, height: metrics.size * 0.05)
                    .rotationEffect(.degrees(18))
            }
        }
    }

    private func flowerView(metrics: FanTuanMetrics, color: Color) -> some View {
        ZStack {
            ForEach(0..<5, id: \.self) { petal in
                Ellipse()
                    .fill(color)
                    .frame(width: metrics.size * 0.026, height: metrics.size * 0.05)
                    .offset(y: -metrics.size * 0.018)
                    .rotationEffect(.degrees(Double(petal) * 72))
            }

            Circle()
                .fill(Color(red: 0.99, green: 0.84, blue: 0.48))
                .frame(width: metrics.size * 0.02, height: metrics.size * 0.02)
        }
    }

    private func sparkle(size: CGFloat, color: Color) -> some View {
        StarShape(points: 5, innerRatio: 0.42)
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.2), radius: size * 0.08, x: 0, y: size * 0.03)
    }

    private func rainDrop(size: CGFloat) -> some View {
        Capsule(style: .continuous)
            .fill(Color(red: 0.55, green: 0.81, blue: 1))
            .frame(width: size * 0.46, height: size)
            .rotationEffect(.degrees(12))
    }

    private var eyeStyle: FanTuanEyeStyle {
        switch asset {
        case .sleepy, .rainy:
            return .sleepy
        case .happy, .eating:
            return .happy
        case .starving:
            return .cross
        case .tap:
            return .wink
        default:
            return .dot
        }
    }

    private var mouthStyle: FanTuanMouthStyle {
        switch asset {
        case .hungry, .excited, .eating:
            return .open
        case .sleepy:
            return .smallO
        case .rainy, .starving:
            return .flat
        default:
            return .smile
        }
    }

    private var blushOpacity: Double {
        switch asset {
        case .happy:
            return 0.95
        case .tap, .excited, .eating:
            return 0.8
        case .starving:
            return 0.4
        default:
            return 0.65
        }
    }

    private var chewPulse: CGFloat {
        CGFloat(abs(sin(progress * .pi * 4)))
    }

    private var sparklePulse: CGFloat {
        0.5 + CGFloat(abs(sin(progress * .pi * 2.4)))
    }

    private var droolAlpha: Double {
        guard asset == .hungry else { return 0 }
        return 0.4 + 0.35 * abs(sin(progress * .pi * 3))
    }

    private var blinkScale: CGFloat {
        guard asset == .idle else { return 1 }
        let windows = [(0.24, 0.28), (0.62, 0.66)]
        for window in windows where progress >= window.0 && progress <= window.1 {
            let local = (progress - window.0) / (window.1 - window.0)
            let amount = abs(local - 0.5) * 2
            return max(0.12, CGFloat(amount))
        }
        return 1
    }

    private var questionOpacity: Double {
        guard asset == .tap else { return 0 }
        if progress < 0.14 { return progress / 0.14 }
        if progress > 0.82 { return max(0, (1 - progress) / 0.18) }
        return 1
    }

    private var questionScale: CGFloat {
        guard asset == .tap else { return 1 }
        return 0.65 + CGFloat(min(1, progress / 0.2)) * 0.4
    }

    private func motion(for metrics: FanTuanMetrics) -> FanTuanMotion {
        let wave = CGFloat(sin(progress * .pi * 2))
        let pulse = CGFloat(abs(sin(progress * .pi * 2)))
        let quickWave = CGFloat(sin(progress * .pi * 6))

        switch asset {
        case .idle:
            return FanTuanMotion(x: 0, y: -metrics.size * 0.035 * wave, rotation: 0, scaleX: 1, scaleY: 1)
        case .hungry:
            return FanTuanMotion(x: metrics.size * 0.03 * quickWave, y: -metrics.size * 0.01 * pulse, rotation: Double(quickWave) * 1.4, scaleX: 1, scaleY: 1)
        case .sleepy:
            return FanTuanMotion(x: 0, y: metrics.size * 0.018 * wave, rotation: Double(wave) * 4, scaleX: 1, scaleY: 1)
        case .excited:
            return FanTuanMotion(x: 0, y: -metrics.size * 0.1 * pulse, rotation: 0, scaleX: 1 + pulse * 0.02, scaleY: 1 - pulse * 0.03)
        case .rainy:
            return FanTuanMotion(x: metrics.size * 0.018 * quickWave, y: 0, rotation: Double(quickWave) * 2, scaleX: 0.97 + pulse * 0.02, scaleY: 0.97 + pulse * 0.02)
        case .eating:
            return FanTuanMotion(x: 0, y: -metrics.size * 0.018 * pulse, rotation: 0, scaleX: 1 + chewPulse * 0.08, scaleY: 1 - chewPulse * 0.1)
        case .happy:
            return FanTuanMotion(x: 0, y: -metrics.size * 0.026 * pulse, rotation: Double(wave) * 9, scaleX: 1, scaleY: 1)
        case .starving:
            return FanTuanMotion(x: metrics.size * 0.016 * quickWave, y: metrics.size * 0.035, rotation: Double(quickWave) * 1.6, scaleX: 0.84 + pulse * 0.03, scaleY: 0.76 + pulse * 0.02)
        case .tap:
            let bounce = CGFloat(sin(min(progress, 1) * .pi))
            return FanTuanMotion(x: 0, y: -metrics.size * 0.085 * bounce, rotation: Double(wave) * 4, scaleX: 1 + bounce * 0.16, scaleY: 1 - bounce * 0.08)
        }
    }
}

private struct FanTuanMetrics {
    let size: CGFloat

    var bodyWidth: CGFloat { size * 0.8 }
    var bodyHeight: CGFloat { size * 0.84 }
    var shadowWidth: CGFloat { size * 0.46 }
    var shadowHeight: CGFloat { size * 0.11 }
    var outlineWidth: CGFloat { size * 0.018 }
    var noriWidth: CGFloat { size * 0.26 }
    var noriHeight: CGFloat { size * 0.17 }
    var noriRadius: CGFloat { size * 0.045 }
    var eyeWidth: CGFloat { size * 0.17 }
    var eyeHeight: CGFloat { size * 0.17 }
    var eyeSpacing: CGFloat { size * 0.15 }
    var mouthWidth: CGFloat { size * 0.13 }
    var mouthHeight: CGFloat { size * 0.16 }
    var cheekWidth: CGFloat { size * 0.15 }
    var cheekHeight: CGFloat { size * 0.11 }
    var footWidth: CGFloat { size * 0.16 }
    var footHeight: CGFloat { size * 0.29 }
    var beltWidth: CGFloat { size * 0.82 }
    var beltHeight: CGFloat { size * 0.16 }
    var beltRadius: CGFloat { size * 0.08 }
    var bibWidth: CGFloat { size * 0.34 }
    var bibHeight: CGFloat { size * 0.23 }
}

private struct FanTuanMotion {
    var x: CGFloat
    var y: CGFloat
    var rotation: Double
    var scaleX: CGFloat
    var scaleY: CGFloat
}

private enum FanTuanEyeStyle {
    case dot
    case sleepy
    case happy
    case wink
    case cross
}

private enum FanTuanMouthStyle {
    case smile
    case open
    case smallO
    case flat
}

private struct OnigiriShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let top = CGPoint(x: rect.midX, y: rect.minY + h * 0.02)
        let leftTop = CGPoint(x: rect.minX + w * 0.16, y: rect.minY + h * 0.3)
        let leftBottom = CGPoint(x: rect.minX + w * 0.08, y: rect.maxY - h * 0.16)
        let bottom = CGPoint(x: rect.midX, y: rect.maxY)
        let rightBottom = CGPoint(x: rect.maxX - w * 0.08, y: rect.maxY - h * 0.16)
        let rightTop = CGPoint(x: rect.maxX - w * 0.16, y: rect.minY + h * 0.3)

        var path = Path()
        path.move(to: top)
        path.addQuadCurve(to: leftTop, control: CGPoint(x: rect.minX + w * 0.32, y: rect.minY + h * 0.05))
        path.addQuadCurve(to: leftBottom, control: CGPoint(x: rect.minX - w * 0.02, y: rect.minY + h * 0.5))
        path.addQuadCurve(to: bottom, control: CGPoint(x: rect.minX + w * 0.24, y: rect.maxY + h * 0.04))
        path.addQuadCurve(to: rightBottom, control: CGPoint(x: rect.maxX - w * 0.24, y: rect.maxY + h * 0.04))
        path.addQuadCurve(to: rightTop, control: CGPoint(x: rect.maxX + w * 0.02, y: rect.minY + h * 0.5))
        path.addQuadCurve(to: top, control: CGPoint(x: rect.maxX - w * 0.32, y: rect.minY + h * 0.05))
        return path
    }
}

private struct RiceGrainShape: Shape {
    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: min(rect.width, rect.height) / 2, style: .continuous)
            .path(in: rect)
    }
}

private struct BibShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.08)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control: CGPoint(x: rect.maxX - rect.width * 0.02, y: rect.maxY - rect.height * 0.12)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY),
            control: CGPoint(x: rect.minX + rect.width * 0.02, y: rect.maxY - rect.height * 0.12)
        )
        path.closeSubpath()
        return path
    }
}

private struct CloudMotifShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let y = rect.midY
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.08, y: y))
        path.addCurve(
            to: CGPoint(x: rect.midX, y: y),
            control1: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY),
            control2: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.08, y: y),
            control1: CGPoint(x: rect.minX + rect.width * 0.64, y: rect.minY),
            control2: CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.maxY)
        )
        return path
    }
}

private struct RoundMedallionShape: Shape {
    func path(in rect: CGRect) -> Path {
        Circle().path(in: rect)
    }
}

private struct StarShape: Shape {
    let points: Int
    let innerRatio: CGFloat

    func path(in rect: CGRect) -> Path {
        guard points >= 2 else { return Path() }

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * innerRatio
        let angleStep = .pi / Double(points)

        var path = Path()
        for index in 0..<(points * 2) {
            let radius = index.isMultiple(of: 2) ? outerRadius : innerRadius
            let angle = (Double(index) * angleStep) - (.pi / 2)
            let point = CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius,
                y: center.y + CGFloat(sin(angle)) * radius
            )

            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

private struct GrainPlacement {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    let rotation: Double
    let opacity: Double
}

private let grainLayout: [GrainPlacement] = [
    .init(x: -0.22, y: -0.25, width: 0.034, height: 0.013, rotation: -28, opacity: 0.95),
    .init(x: -0.15, y: -0.29, width: 0.03, height: 0.012, rotation: 18, opacity: 0.92),
    .init(x: -0.06, y: -0.32, width: 0.032, height: 0.012, rotation: -36, opacity: 0.88),
    .init(x: 0.05, y: -0.28, width: 0.03, height: 0.012, rotation: 12, opacity: 0.84),
    .init(x: 0.17, y: -0.22, width: 0.04, height: 0.014, rotation: 8, opacity: 0.9),
    .init(x: 0.23, y: -0.12, width: 0.034, height: 0.013, rotation: 54, opacity: 0.86),
    .init(x: -0.28, y: -0.08, width: 0.036, height: 0.014, rotation: -42, opacity: 0.88),
    .init(x: -0.3, y: 0.02, width: 0.034, height: 0.013, rotation: 10, opacity: 0.82),
    .init(x: -0.26, y: 0.16, width: 0.03, height: 0.012, rotation: -8, opacity: 0.8),
    .init(x: 0.28, y: 0.14, width: 0.034, height: 0.013, rotation: -48, opacity: 0.84),
    .init(x: 0.2, y: 0.25, width: 0.03, height: 0.012, rotation: 20, opacity: 0.8),
    .init(x: -0.08, y: 0.29, width: 0.034, height: 0.013, rotation: -15, opacity: 0.78),
]

private struct FlowerPlacement {
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let color: Color
}

private let flowerLayout: [FlowerPlacement] = [
    .init(x: -0.11, y: -0.04, size: 0.08, color: Color(red: 0.95, green: 0.49, blue: 0.29)),
    .init(x: 0.11, y: -0.05, size: 0.08, color: Color(red: 0.98, green: 0.66, blue: 0.39)),
    .init(x: -0.14, y: 0.07, size: 0.055, color: Color(red: 0.97, green: 0.74, blue: 0.77)),
    .init(x: 0.14, y: 0.08, size: 0.055, color: Color(red: 0.56, green: 0.75, blue: 0.67)),
]
