import Foundation

/// Describes a single shader effect in the gallery.
struct ShaderDescriptor {
    let id: String
    let title: String
    let fragmentFunction: String   // Metal function name, e.g. "fs_fluid_amber"
    let needsCompute: Bool         // true = has a compute kernel to dispatch before render
    let computeFunction: String?   // Metal compute function name, if any
}

/// All registered shaders. Add entries here as shaders are ported.
let shaderRegistry: [ShaderDescriptor] = [
    // Phase 0
    ShaderDescriptor(id: "fluid-amber", title: "Fluid Amber",
                     fragmentFunction: "fs_fluid_amber",
                     needsCompute: false, computeFunction: nil),
    // Phase 1 — Batch 1
    ShaderDescriptor(id: "burning-film", title: "Burning Film",
                     fragmentFunction: "fs_burning_film",
                     needsCompute: false, computeFunction: nil),
    ShaderDescriptor(id: "silk-cascade", title: "Silk Cascade",
                     fragmentFunction: "fs_silk_cascade",
                     needsCompute: false, computeFunction: nil),
    ShaderDescriptor(id: "bioluminescence", title: "Bioluminescence",
                     fragmentFunction: "fs_bioluminescence",
                     needsCompute: false, computeFunction: nil),
    ShaderDescriptor(id: "chromatic-bloom", title: "Chromatic Bloom",
                     fragmentFunction: "fs_chromatic_bloom",
                     needsCompute: false, computeFunction: nil),
    ShaderDescriptor(id: "vortex", title: "Vortex",
                     fragmentFunction: "fs_vortex",
                     needsCompute: false, computeFunction: nil),
    // Phase 1 — Batch 2
    ShaderDescriptor(id: "chladni-resonance", title: "Chladni Resonance",
                     fragmentFunction: "fs_chladni_resonance",
                     needsCompute: false, computeFunction: nil),
    ShaderDescriptor(id: "moire-interference", title: "Moiré Interference",
                     fragmentFunction: "fs_moire_interference",
                     needsCompute: false, computeFunction: nil),
    ShaderDescriptor(id: "golden-throne", title: "Golden Throne",
                     fragmentFunction: "fs_golden_throne",
                     needsCompute: false, computeFunction: nil),
    ShaderDescriptor(id: "kaleidoscope-runway", title: "Kaleidoscope Runway",
                     fragmentFunction: "fs_kaleidoscope_runway",
                     needsCompute: false, computeFunction: nil),
    ShaderDescriptor(id: "neon-drip", title: "Neon Drip",
                     fragmentFunction: "fs_neon_drip",
                     needsCompute: false, computeFunction: nil),
    // Phase 1 — Batch 3
    ShaderDescriptor(id: "eclipse-glow", title: "Eclipse Glow",
                     fragmentFunction: "fs_eclipse_glow",
                     needsCompute: false, computeFunction: nil),
    ShaderDescriptor(id: "aurora-veil", title: "Aurora Veil",
                     fragmentFunction: "fs_aurora_veil",
                     needsCompute: false, computeFunction: nil),
    ShaderDescriptor(id: "moonlit-ripple", title: "Moonlit Ripple",
                     fragmentFunction: "fs_moonlit_ripple",
                     needsCompute: false, computeFunction: nil),
    ShaderDescriptor(id: "diamond-caustics", title: "Diamond Caustics",
                     fragmentFunction: "fs_diamond_caustics",
                     needsCompute: false, computeFunction: nil),
    ShaderDescriptor(id: "smolder", title: "Smolder",
                     fragmentFunction: "fs_smolder",
                     needsCompute: false, computeFunction: nil),
    // Phase 1 — Batch 4
    ShaderDescriptor(id: "stardust-veil", title: "Stardust Veil",
                     fragmentFunction: "fs_stardust_veil",
                     needsCompute: false, computeFunction: nil),
    ShaderDescriptor(id: "shifting-veils", title: "Shifting Veils",
                     fragmentFunction: "fs_shifting_veils",
                     needsCompute: false, computeFunction: nil),
    ShaderDescriptor(id: "painted-strata", title: "Painted Strata",
                     fragmentFunction: "fs_painted_strata",
                     needsCompute: false, computeFunction: nil),
    ShaderDescriptor(id: "liquid-gold", title: "Liquid Gold",
                     fragmentFunction: "fs_liquid_gold",
                     needsCompute: false, computeFunction: nil),
]
