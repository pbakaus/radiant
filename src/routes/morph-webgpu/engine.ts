import { SHADER_WGSL } from './shader.wgsl';
import { UNIFORM_BYTES } from './presets';

// Minimal blit shader: fullscreen triangle → sample half-res texture with linear filter.
// Grain runs in main shader at half-res; if full-res grain is desired in future,
// it can be moved here at the cost of a small uniform re-bind.
const BLIT_WGSL = /* wgsl */`
struct VSOut {
  @builtin(position) pos: vec4f,
  @location(0) uv: vec2f,
}

@vertex
fn vs_blit(@builtin(vertex_index) vi: u32) -> VSOut {
  var pos = array<vec2f, 3>(vec2f(-1.0, -1.0), vec2f(3.0, -1.0), vec2f(-1.0, 3.0));
  let p = pos[vi];
  // NDC (-1..1) → UV (0..1), flipping Y because NDC +Y is up, UV +V is down
  let uv = p * vec2f(0.5, -0.5) + vec2f(0.5);
  return VSOut(vec4f(p, 0.0, 1.0), uv);
}

@group(0) @binding(0) var blit_sampler: sampler;
@group(0) @binding(1) var blit_tex: texture_2d<f32>;

@fragment
fn fs_blit(in: VSOut) -> @location(0) vec4f {
  return textureSample(blit_tex, blit_sampler, in.uv);
}
`;

export class MorphEngine {
	private device: GPUDevice;
	private context: GPUCanvasContext;
	private uniformBuffer: GPUBuffer;
	private format: GPUTextureFormat;

	// Main (full-feature) render bundle — targets half-res texture, stable across frames
	private renderBundle: GPURenderBundle;

	// Half-resolution intermediate texture
	private halfResTexture: GPUTexture;

	// Blit pipeline and bind group (bind group recreated on resize)
	private blitPipeline: GPURenderPipeline;
	private blitBindGroup: GPUBindGroup;

	// Cached main pipeline and bind group needed to rebuild render bundle on resize
	private mainPipeline: GPURenderPipeline;
	private mainBindGroup: GPUBindGroup;

	private constructor(
		device: GPUDevice,
		context: GPUCanvasContext,
		uniformBuffer: GPUBuffer,
		format: GPUTextureFormat,
		renderBundle: GPURenderBundle,
		halfResTexture: GPUTexture,
		blitPipeline: GPURenderPipeline,
		blitBindGroup: GPUBindGroup,
		mainPipeline: GPURenderPipeline,
		mainBindGroup: GPUBindGroup,
	) {
		this.device = device;
		this.context = context;
		this.uniformBuffer = uniformBuffer;
		this.format = format;
		this.renderBundle = renderBundle;
		this.halfResTexture = halfResTexture;
		this.blitPipeline = blitPipeline;
		this.blitBindGroup = blitBindGroup;
		this.mainPipeline = mainPipeline;
		this.mainBindGroup = mainBindGroup;
	}

	static async create(canvas: HTMLCanvasElement): Promise<MorphEngine> {
		const adapter = await navigator.gpu?.requestAdapter();
		if (!adapter) throw new Error('WebGPU not available');
		const device = await adapter.requestDevice();

		const context = canvas.getContext('webgpu')!;
		const format = navigator.gpu.getPreferredCanvasFormat();
		context.configure({ device, format, alphaMode: 'opaque' });

		const mainModule = device.createShaderModule({ code: SHADER_WGSL });
		const blitModule = device.createShaderModule({ code: BLIT_WGSL });

		const uniformBuffer = device.createBuffer({
			size: UNIFORM_BYTES,
			usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
		});

		const mainBindGroupLayout = device.createBindGroupLayout({
			entries: [{
				binding: 0,
				visibility: GPUShaderStage.FRAGMENT | GPUShaderStage.VERTEX,
				buffer: { type: 'uniform' }
			}]
		});

		const mainBindGroup = device.createBindGroup({
			layout: mainBindGroupLayout,
			entries: [{ binding: 0, resource: { buffer: uniformBuffer } }]
		});

		// FBM_MAX_OCTAVES=3 matches all current presets; passed as an override constant
		// so the compiler can unroll the loop and eliminate dead iterations.
		const FBM_MAX_OCTAVES = 3;
		const mainPipeline = device.createRenderPipeline({
			layout: device.createPipelineLayout({ bindGroupLayouts: [mainBindGroupLayout] }),
			vertex: { module: mainModule, entryPoint: 'vs', constants: { FBM_MAX_OCTAVES } },
			fragment: {
				module: mainModule,
				entryPoint: 'fs',
				targets: [{ format }],
				constants: { FBM_MAX_OCTAVES }
			},
			primitive: { topology: 'triangle-list' }
		});

		const blitBindGroupLayout = device.createBindGroupLayout({
			entries: [
				{ binding: 0, visibility: GPUShaderStage.FRAGMENT, sampler: { type: 'filtering' } },
				{ binding: 1, visibility: GPUShaderStage.FRAGMENT, texture: { sampleType: 'float' } },
			]
		});

		const blitPipeline = device.createRenderPipeline({
			layout: device.createPipelineLayout({ bindGroupLayouts: [blitBindGroupLayout] }),
			vertex: { module: blitModule, entryPoint: 'vs_blit' },
			fragment: { module: blitModule, entryPoint: 'fs_blit', targets: [{ format }] },
			primitive: { topology: 'triangle-list' }
		});

		const { halfResTexture, blitBindGroup, renderBundle } = MorphEngine._buildHalfResResources(
			device, format, canvas.width, canvas.height,
			mainPipeline, mainBindGroup, blitPipeline, blitBindGroupLayout
		);

		return new MorphEngine(
			device, context, uniformBuffer, format,
			renderBundle, halfResTexture,
			blitPipeline, blitBindGroup,
			mainPipeline, mainBindGroup,
		);
	}

	/** Recreate half-res texture, render bundle, and blit bind group for new canvas dimensions. */
	resize(width: number, height: number): void {
		this.halfResTexture.destroy();

		const blitBindGroupLayout = this.blitPipeline.getBindGroupLayout(0);
		const resources = MorphEngine._buildHalfResResources(
			this.device, this.format, width, height,
			this.mainPipeline, this.mainBindGroup,
			this.blitPipeline, blitBindGroupLayout
		);

		this.halfResTexture = resources.halfResTexture;
		this.blitBindGroup = resources.blitBindGroup;
		this.renderBundle = resources.renderBundle;
	}

	private static _buildHalfResResources(
		device: GPUDevice,
		format: GPUTextureFormat,
		canvasWidth: number,
		canvasHeight: number,
		mainPipeline: GPURenderPipeline,
		mainBindGroup: GPUBindGroup,
		blitPipeline: GPURenderPipeline,
		blitBindGroupLayout: GPUBindGroupLayout,
	): { halfResTexture: GPUTexture; blitBindGroup: GPUBindGroup; renderBundle: GPURenderBundle } {
		const halfW = Math.max(1, Math.floor(canvasWidth / 2));
		const halfH = Math.max(1, Math.floor(canvasHeight / 2));

		const halfResTexture = device.createTexture({
			size: [halfW, halfH],
			format,
			usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING,
		});

		// Blit bind group references the stable half-res texture view
		const blitSampler = device.createSampler({ magFilter: 'linear', minFilter: 'linear' });
		const blitBindGroup = device.createBindGroup({
			layout: blitBindGroupLayout,
			entries: [
				{ binding: 0, resource: blitSampler },
				{ binding: 1, resource: halfResTexture.createView() },
			]
		});

		// Main render bundle targets the half-res texture view (fixed target — stable for bundling)
		const bundleEncoder = device.createRenderBundleEncoder({
			colorFormats: [format]
		});
		bundleEncoder.setPipeline(mainPipeline);
		bundleEncoder.setBindGroup(0, mainBindGroup);
		bundleEncoder.draw(3);
		const renderBundle = bundleEncoder.finish();

		return { halfResTexture, blitBindGroup, renderBundle };
	}

	// GPU frame completion tracking
	private _gpuFrames = 0;
	private _gpuFpsTime = 0;
	private _gpuFps = 0;

	get gpuFps(): number { return this._gpuFps; }

	render(uniforms: Float32Array): void {
		this.device.queue.writeBuffer(this.uniformBuffer, 0, uniforms);

		const encoder = this.device.createCommandEncoder();

		// Pass 1: main shader → half-res texture (bundled draw call, near-zero CPU overhead)
		const mainPass = encoder.beginRenderPass({
			colorAttachments: [{
				view: this.halfResTexture.createView(),
				loadOp: 'clear' as const,
				storeOp: 'store' as const,
				clearValue: { r: 0.04, g: 0.04, b: 0.04, a: 1 },
			}]
		});
		mainPass.executeBundles([this.renderBundle]);
		mainPass.end();

		// Pass 2: blit half-res → swap chain with linear upscale
		// Cannot use a render bundle here because the swap chain view changes every frame.
		const blitPass = encoder.beginRenderPass({
			colorAttachments: [{
				view: this.context.getCurrentTexture().createView(),
				loadOp: 'clear' as const,
				storeOp: 'store' as const,
				clearValue: { r: 0, g: 0, b: 0, a: 1 },
			}]
		});
		blitPass.setPipeline(this.blitPipeline);
		blitPass.setBindGroup(0, this.blitBindGroup);
		blitPass.draw(3);
		blitPass.end();

		this.device.queue.submit([encoder.finish()]);

		// Count actual GPU completions per second
		this.device.queue.onSubmittedWorkDone().then(() => {
			this._gpuFrames++;
			const now = performance.now();
			if (now - this._gpuFpsTime > 1000) {
				this._gpuFps = this._gpuFrames;
				this._gpuFrames = 0;
				this._gpuFpsTime = now;
			}
		});
	}

	destroy(): void {
		this.halfResTexture.destroy();
		this.uniformBuffer.destroy();
		this.device.destroy();
	}
}
