import Foundation
import CoreVideo

/// CVDisplayLink-based frame pacer. Java's render thread blocks in
/// awaitPresentWindow() until the next display refresh window, aligning buffer
/// swaps with the display (ProMotion-aware) to cut frame-pacing stutter.
final class FramePacer {
    static let shared = FramePacer()

    private var displayLink: CVDisplayLink?
    private let semaphore = DispatchSemaphore(value: 0)
    private var running = false

    private init() {}

    func start() {
        guard !running else { return }
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let link else { return }

        CVDisplayLinkSetOutputCallback(link, { _, _, _, _, _, userInfo in
            let pacer = Unmanaged<FramePacer>.fromOpaque(userInfo!).takeUnretainedValue()
            pacer.semaphore.signal()
            return kCVReturnSuccess
        }, Unmanaged.passUnretained(self).toOpaque())

        CVDisplayLinkStart(link)
        displayLink = link
        running = true
    }

    /// Blocks the calling (render) thread until the next vsync tick, with a
    /// safety timeout so a display reconfigure can never hang the game.
    func awaitPresentWindow() {
        guard running else { return }
        _ = semaphore.wait(timeout: .now() + .milliseconds(50))
    }

    func stop() {
        guard running, let link = displayLink else { return }
        CVDisplayLinkStop(link)
        displayLink = nil
        running = false
        semaphore.signal()   // release any blocked waiter
    }
}
