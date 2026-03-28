import ScreenSaver
import Metal
import QuartzCore
import CoreVideo

// MARK: - Constants

private let UNIFORM_FLOATS = 64
private let UNIFORM_BYTES = UNIFORM_FLOATS * 4

// Uniform buffer indices
private let U_TIME: Int = 0
private let U_ZOOM: Int = 1
private let U_HUE_SHIFT: Int = 2
private let U_RES_X: Int = 4
private let U_RES_Y: Int = 5
private let U_MOUSE_X: Int = 6
private let U_MOUSE_Y: Int = 7
private let U_ZOOM_CENTER_X: Int = 8
private let U_ZOOM_CENTER_Y: Int = 9
private let U_COLOUR_VAR_STR: Int = 61

// Timing
private let HUE_CYCLE_S: Float = 300.0
private let COLOUR_VAR_CYCLE_S: Float = 20.0
private let KALEIDO_RAMP_TIME: Float = 15.0 // timeSec units (= 60 real seconds)
private let TIME_DIVISOR: Double = 4000.0 // quarter speed: elapsed_ms / 4000

// Render at half resolution for 4× fewer fragment invocations.
// CAMetalLayer bilinear upscales to the display — imperceptible on smooth noise fields.
private let RESOLUTION_SCALE: CGFloat = 0.5

// MARK: - Preset data

// 10 presets, each 43 floats. Layout:
// [oct, decay, fmul, scale, w1, w2,
//  orbN, orbR, orbI, orbMode, fold, foldF, norm, diff, spec, specP, fres, edge,
//  ridge, waveStr, waveF,
//  sR,sG,sB, mR,mG,mB, bR,bG,bB, hR,hG,hB,
//  orbSharp, moireStr, burnStr, burnSpeed, spiralStr, spiralArms,
//  kaleidoStr, kaleidoSeg, chromaStr, chladniStr, chladniMode]
private let P: [[Float]] = [
    // 0: Flowing warp (fluid-amber)
    [3, 0.48, 2.10, 0.70, 3.2, 2.5,  7, 0.25, 0, 0, 0, 2, 0, 0, 0, 40, 0, 0.6,
     0.35, 0, 2,
     0.03, 0.025, 0.01, 0.20, 0.14, 0.07, 0.78, 0.58, 0.24, 0.95, 0.85, 0.50, 0, 0, 0, 0.5, 0, 5, 0, 8, 0, 0, 3],
    // 1: Orb field (chromatic-bloom)
    [3, 0.15, 2.0, 0.25, 0, 0,  7, 0.30, 1.5, 1.0, 0, 2, 0, 0, 0, 40, 0, 0,
     0, 0, 2,
     0.01, 0.008, 0.005, 0.04, 0.03, 0.02, 0.20, 0.15, 0.08, 0.80, 0.65, 0.35, 0, 0, 0, 0.5, 0, 5, 0, 8, 0.15, 0, 3],
    // 2: Silk folds (silk-cascade)
    [3, 0.30, 2.0, 0.50, 0.15, 0,  7, 0.25, 0, 0, 1.0, 3.0, 1.0, 0.75, 0.85, 42, 0.15, 0,
     0, 0, 2,
     0.04, 0.025, 0.015, 0.35, 0.18, 0.10, 0.85, 0.55, 0.30, 1.0, 0.88, 0.65, 0, 0, 0, 0.5, 0, 5, 0, 8, 0, 0, 3],
    // 3: Ocean waves (bioluminescence)
    [3, 0.42, 2.03, 0.65, 0.8, 0.3,  7, 0.25, 0, 0, 0, 2, 0.4, 0.25, 0, 40, 0, 0,
     0, 0.8, 3.0,
     0.02, 0.025, 0.03, 0.08, 0.18, 0.15, 0.40, 0.60, 0.45, 0.90, 0.80, 0.55, 0, 0, 0, 0.5, 0, 5, 0, 8, 0, 0, 3],
    // 4: Neon metaballs (neon-drip)
    [3, 0.15, 2.0, 0.30, 0, 0,  7, 0.28, 1.8, 1.0, 0, 2, 0, 0, 0, 40, 0, 0,
     0, 0, 2,
     0.005, 0.005, 0.01, 0.03, 0.02, 0.06, 0.15, 0.08, 0.30, 0.90, 0.50, 0.80, 1.0, 0, 0, 0.5, 0, 5, 0, 8, 0.2, 0, 3],
    // 5: Moire beats (moire-interference)
    [3, 0.15, 2.0, 0.40, 0, 0,  7, 0.25, 0, 0, 0, 2, 0, 0, 0, 40, 0, 0,
     0, 0, 2,
     0.01, 0.01, 0.008, 0.08, 0.06, 0.04, 0.50, 0.35, 0.15, 0.85, 0.75, 0.40, 0, 1.0, 0, 0.5, 0, 5, 0, 8, 0.1, 0, 3],
    // 6: Burning film (burning-film)
    [3, 0.48, 2.10, 0.65, 2.5, 1.8,  7, 0.25, 0, 0, 0, 2, 0, 0, 0, 40, 0, 0.8,
     0.4, 0, 2,
     0.02, 0.01, 0.005, 0.25, 0.10, 0.03, 0.80, 0.45, 0.12, 1.0, 0.85, 0.40, 0, 0, 1.0, 0.4, 0, 5, 0, 8, 0, 0, 3],
    // 7: Spiral vortex (vortex)
    [3, 0.42, 2.05, 0.55, 1.0, 0.5,  7, 0.25, 0, 0, 0, 2, 0, 0, 0, 40, 0, 0.2,
     0, 0, 2,
     0.02, 0.015, 0.008, 0.12, 0.08, 0.04, 0.55, 0.40, 0.18, 0.90, 0.75, 0.40, 0, 0, 0, 0.5, 1.0, 5, 0, 8, 0, 0, 3],
    // 8: Kaleidoscope mandala (kaleidoscope-runway)
    [3, 0.40, 2.05, 0.60, 1.5, 0.8,  7, 0.25, 0, 0, 0, 2, 0, 0, 0, 40, 0, 0.3,
     0.2, 0, 2,
     0.02, 0.015, 0.01, 0.15, 0.10, 0.06, 0.65, 0.45, 0.20, 0.95, 0.80, 0.45, 0, 0, 0, 0.5, 0, 5, 1.0, 8, 0, 0, 3],
    // 9: Chladni cymatics (chladni-resonance)
    [3, 0.15, 2.0, 0.40, 0, 0,  7, 0.25, 0, 0, 0, 2, 0, 0, 0, 40, 0, 0.2,
     0, 0, 2,
     0.01, 0.01, 0.008, 0.06, 0.05, 0.04, 0.45, 0.35, 0.20, 0.90, 0.80, 0.50, 0, 0, 0, 0.5, 0, 5, 0, 8, 0, 1.0, 3],
]

// Map preset array index to uniform buffer index
private let MAP: [Int] = [
    3, 10, 11, 12, 13, 14,          // fbm + warp
    15, 16, 17, 18,                  // orbs
    19, 20, 21, 22, 23, 24, 25, 26, // fold + lighting + edge
    29, 48, 49,                      // ridge, waves
    32, 33, 34, 36, 37, 38, 40, 41, 42, 44, 45, 46, // colors
    50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60       // t2+t3 params
]

private let N_PRESETS = 10
private let N_PARAMS = 43

// MARK: - Drift functions

/// Incommensurate sine sums: infinitely smooth, no cell boundaries.
private func drift(_ time: Float, speed: Float, seed: Float) -> Float {
    let t = time * speed
    let s = seed * 1.3717
    let v: Float = 0.25 * (
        sin(t * 1.0 + s * 2.399) +
        sin(t * 1.6180339 + s * 3.147) +
        sin(t * 2.2360679 + s * 1.893) +
        sin(t * 0.7320508 + s * 4.261)
    )
    return v * 0.5 + 0.5
}

// MARK: - File logging (NSLog suppressed in screen saver sandbox)

private let logFile = NSHomeDirectory() + "/morph-screensaver.log"

private func sslog(_ msg: String) {
    let ts = String(format: "%.3f", CACurrentMediaTime())
    let line = "[\(ts)] \(msg)\n"
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logFile) {
            if let fh = FileHandle(forWritingAtPath: logFile) {
                fh.seekToEndOfFile()
                fh.write(data)
                fh.closeFile()
            }
        } else {
            FileManager.default.createFile(atPath: logFile, contents: data)
        }
    }
}

// MARK: - CVDisplayLink callback (C function, no captures)

private func displayLinkCallback(
    _ displayLink: CVDisplayLink,
    _ inNow: UnsafePointer<CVTimeStamp>,
    _ inOutputTime: UnsafePointer<CVTimeStamp>,
    _ flagsIn: CVOptionFlags,
    _ flagsOut: UnsafeMutablePointer<CVOptionFlags>,
    _ context: UnsafeMutableRawPointer?
) -> CVReturn {
    guard let context = context else { return kCVReturnError }
    let view = Unmanaged<MorphScreenSaverView>.fromOpaque(context).takeUnretainedValue()
    DispatchQueue.main.async { view.renderFrame() }
    return kCVReturnSuccess
}

// MARK: - Screen Saver View

@objc(MorphScreenSaverView)
class MorphScreenSaverView: ScreenSaverView {

    // Metal state
    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?
    private var uniformBuffer: MTLBuffer?
    private var metalLayer: CAMetalLayer?

    // CVDisplayLink for vsync'd rendering
    private var displayLink: CVDisplayLink?

    // Timing
    private var startTime: CFTimeInterval = 0

    // Pre-allocated proximity array
    private var prox = [Float](repeating: 0, count: N_PRESETS)

    // MARK: - Init

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        sslog("init frame=\(frame) isPreview=\(isPreview)")
        setupMetal()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupMetal()
    }

    private func setupMetal() {
        startTime = CACurrentMediaTime()

        guard let device = MTLCreateSystemDefaultDevice() else {
            sslog("No Metal device")
            return
        }
        self.device = device

        guard let queue = device.makeCommandQueue() else {
            sslog("Failed to create command queue")
            return
        }
        self.commandQueue = queue

        // Create CAMetalLayer
        let metalLayer = CAMetalLayer()
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.displaySyncEnabled = true
        metalLayer.frame = self.bounds
        metalLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        self.wantsLayer = true
        self.layer = metalLayer
        self.metalLayer = metalLayer

        // Load shader library from bundle
        guard let library = loadShaderLibrary(device: device) else {
            sslog("Failed to load shader library")
            return
        }

        guard let vertexFunc = library.makeFunction(name: "vs"),
              let fragmentFunc = library.makeFunction(name: "fs") else {
            sslog("Failed to find shader functions")
            return
        }

        // Render pipeline
        let pipelineDesc = MTLRenderPipelineDescriptor()
        pipelineDesc.vertexFunction = vertexFunc
        pipelineDesc.fragmentFunction = fragmentFunc
        pipelineDesc.colorAttachments[0].pixelFormat = .bgra8Unorm

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDesc)
        } catch {
            sslog("Pipeline creation failed: \(error)")
            return
        }

        // Uniform buffer (256 bytes)
        uniformBuffer = device.makeBuffer(length: UNIFORM_BYTES, options: .storageModeShared)
    }

    private func loadShaderLibrary(device: MTLDevice) -> MTLLibrary? {
        let bundle = Bundle(for: type(of: self))
        // Try pre-compiled metallib
        if let libURL = bundle.url(forResource: "default", withExtension: "metallib") {
            do {
                return try device.makeLibrary(URL: libURL)
            } catch {
                sslog("Pre-compiled metallib failed: \(error)")
            }
        }
        // Fallback: compile from .metal source at runtime
        if let metalPath = bundle.path(forResource: "Shaders", ofType: "metal") {
            do {
                let source = try String(contentsOfFile: metalPath, encoding: .utf8)
                return try device.makeLibrary(source: source, options: nil)
            } catch {
                sslog("Runtime shader compilation failed: \(error)")
            }
        }
        return device.makeDefaultLibrary()
    }

    // MARK: - Layout

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateLayerSize()
    }

    override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize)
        updateLayerSize()
    }

    private func updateLayerSize() {
        guard let metalLayer = metalLayer else { return }
        let scale = self.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        metalLayer.contentsScale = scale
        metalLayer.frame = self.bounds
        // Half-res: render at RESOLUTION_SCALE of native, bilinear upscaled by the layer
        let w = max(Int(self.bounds.width * scale * RESOLUTION_SCALE), 1)
        let h = max(Int(self.bounds.height * scale * RESOLUTION_SCALE), 1)
        metalLayer.drawableSize = CGSize(width: w, height: h)
    }

    // MARK: - Start / Stop via CVDisplayLink

    override func startAnimation() {
        super.startAnimation()
        startDisplayLink()
    }

    override func stopAnimation() {
        stopDisplayLink()
        super.stopAnimation()
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let link = link else {
            sslog("Failed to create CVDisplayLink")
            return
        }
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(link, displayLinkCallback, selfPtr)
        CVDisplayLinkStart(link)
        self.displayLink = link
        sslog("CVDisplayLink started")
    }

    private func stopDisplayLink() {
        guard let link = displayLink else { return }
        CVDisplayLinkStop(link)
        displayLink = nil
        sslog("CVDisplayLink stopped")
    }

    // MARK: - Animation (called from animateOneFrame AND CVDisplayLink)

    private var frameCount = 0

    // ScreenSaverView's timer still fires — make it a no-op since CVDisplayLink drives rendering
    override func animateOneFrame() {}

    func renderFrame() {
        frameCount += 1

        guard let metalLayer = metalLayer,
              let pipelineState = pipelineState,
              let commandQueue = commandQueue,
              let uniformBuffer = uniformBuffer else { return }

        // Update layer size
        let scale = self.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        metalLayer.frame = self.bounds
        metalLayer.contentsScale = scale
        let drawW = max(Int(self.bounds.width * scale * RESOLUTION_SCALE), 1)
        let drawH = max(Int(self.bounds.height * scale * RESOLUTION_SCALE), 1)
        metalLayer.drawableSize = CGSize(width: drawW, height: drawH)

        if frameCount <= 3 || frameCount % 300 == 0 {
            sslog("frame=\(frameCount) bounds=\(self.bounds) drawableSize=\(metalLayer.drawableSize)")
        }

        guard let drawable = metalLayer.nextDrawable() else { return }

        let now = CACurrentMediaTime()
        let elapsedMs = (now - startTime) * 1000.0
        let timeSec = Float(elapsedMs / TIME_DIVISOR)

        // Fill uniform buffer
        let buf = uniformBuffer.contents().bindMemory(to: Float.self, capacity: UNIFORM_FLOATS)

        // ── Proximity signals ──
        prox[0] = drift(timeSec, speed: 0.018, seed: 1)
        prox[1] = drift(timeSec, speed: 0.037, seed: 2)
        prox[2] = drift(timeSec, speed: 0.025, seed: 3)
        prox[3] = drift(timeSec, speed: 0.042, seed: 5)
        prox[4] = drift(timeSec, speed: 0.028, seed: 13)
        prox[5] = drift(timeSec, speed: 0.020, seed: 17)
        prox[6] = drift(timeSec, speed: 0.039, seed: 19)
        prox[7] = drift(timeSec, speed: 0.033, seed: 23)
        prox[8] = drift(timeSec, speed: 0.025, seed: 29)
        prox[9] = drift(timeSec, speed: 0.035, seed: 31)

        // Power-8 winner-take-all
        var sum: Float = 0.001
        for i in 0..<N_PRESETS {
            let p2 = prox[i] * prox[i]
            let p4 = p2 * p2
            prox[i] = p4 * p4
            sum += prox[i]
        }
        for i in 0..<N_PRESETS {
            prox[i] /= sum
        }

        // Blend toward attractors
        for j in 0..<N_PARAMS {
            var v: Float = 0
            for i in 0..<N_PRESETS {
                v += prox[i] * P[i][j]
            }
            v *= 1.0 + (drift(timeSec, speed: 0.12, seed: Float(j + 60)) - 0.5) * 0.06
            buf[MAP[j]] = v
        }

        // Voronoi always off
        buf[30] = 0
        buf[31] = 4

        // Kaleido startup ramp: 0->1 over first 60 real seconds (timeSec 15)
        let ke = min(Float(1), timeSec / KALEIDO_RAMP_TIME)
        buf[56] *= ke * ke * (3 - 2 * ke) // smoothstep

        buf[27] = 0.4  // vignette
        buf[28] = 0.012 // grain

        // Per-frame uniforms
        buf[U_TIME] = timeSec
        buf[U_ZOOM] = 1.0 + (0.5 + 0.5 * sin(timeSec * 0.05)) * 0.3
        buf[U_HUE_SHIFT] = (timeSec / HUE_CYCLE_S) * Float.pi * 2
        buf[U_COLOUR_VAR_STR] = max(0, sin((timeSec / COLOUR_VAR_CYCLE_S) * Float.pi * 2)) * 0.9

        let drawableSize = metalLayer.drawableSize
        buf[U_RES_X] = Float(drawableSize.width)
        buf[U_RES_Y] = Float(drawableSize.height)
        buf[U_MOUSE_X] = 0
        buf[U_MOUSE_Y] = 0

        // Zoom center: slowly drifts around center
        buf[U_ZOOM_CENTER_X] = 0.5 + drift(timeSec, speed: 0.025, seed: 31) * 0.15 - 0.075
        buf[U_ZOOM_CENTER_Y] = 0.5 + drift(timeSec, speed: 0.02, seed: 32) * 0.15 - 0.075

        // Render
        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture = drawable.texture
        passDesc.colorAttachments[0].loadAction = .clear
        passDesc.colorAttachments[0].storeAction = .store
        passDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1.0)

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDesc) else { return }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    override var hasConfigureSheet: Bool { false }
    override var configureSheet: NSWindow? { nil }

    override func draw(_ rect: NSRect) {
        // Let Metal handle all drawing via CAMetalLayer
    }
}
