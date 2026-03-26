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
    ShaderDescriptor(id: "fluid-amber", title: "Fluid Amber",
                     fragmentFunction: "fs_fluid_amber",
                     needsCompute: false, computeFunction: nil),
]
