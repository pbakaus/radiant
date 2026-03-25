import { SHADER_WGSL } from './shader.wgsl';
import { UNIFORM_BYTES } from './presets';

export class MorphEngine {
	private device: GPUDevice;
	private context: GPUCanvasContext;
	private uniformBuffer: GPUBuffer;
	private renderBundle: GPURenderBundle;
	private format: GPUTextureFormat;

	private constructor(
		device: GPUDevice,
		context: GPUCanvasContext,
		uniformBuffer: GPUBuffer,
		renderBundle: GPURenderBundle,
		format: GPUTextureFormat
	) {
		this.device = device;
		this.context = context;
		this.uniformBuffer = uniformBuffer;
		this.renderBundle = renderBundle;
		this.format = format;
	}

	static async create(canvas: HTMLCanvasElement): Promise<MorphEngine> {
		const adapter = await navigator.gpu?.requestAdapter();
		if (!adapter) throw new Error('WebGPU not available');
		const device = await adapter.requestDevice();

		const context = canvas.getContext('webgpu')!;
		const format = navigator.gpu.getPreferredCanvasFormat();
		context.configure({ device, format, alphaMode: 'opaque' });

		const module = device.createShaderModule({ code: SHADER_WGSL });

		const uniformBuffer = device.createBuffer({
			size: UNIFORM_BYTES,
			usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
		});

		const bindGroupLayout = device.createBindGroupLayout({
			entries: [{
				binding: 0,
				visibility: GPUShaderStage.FRAGMENT | GPUShaderStage.VERTEX,
				buffer: { type: 'uniform' }
			}]
		});

		const bindGroup = device.createBindGroup({
			layout: bindGroupLayout,
			entries: [{ binding: 0, resource: { buffer: uniformBuffer } }]
		});

		// FBM_MAX_OCTAVES=3 matches all current presets; passed as an override constant
		// so the compiler can unroll the loop and eliminate dead iterations.
		const FBM_MAX_OCTAVES = 3;
		const pipeline = device.createRenderPipeline({
			layout: device.createPipelineLayout({ bindGroupLayouts: [bindGroupLayout] }),
			vertex: { module, entryPoint: 'vs', constants: { FBM_MAX_OCTAVES } },
			fragment: {
				module,
				entryPoint: 'fs',
				targets: [{ format }],
				constants: { FBM_MAX_OCTAVES }
			},
			primitive: { topology: 'triangle-list' }
		});

		// Pre-record the draw call as a render bundle — replayed every frame with zero overhead
		const bundleEncoder = device.createRenderBundleEncoder({
			colorFormats: [format]
		});
		bundleEncoder.setPipeline(pipeline);
		bundleEncoder.setBindGroup(0, bindGroup);
		bundleEncoder.draw(3);
		const renderBundle = bundleEncoder.finish();

		return new MorphEngine(device, context, uniformBuffer, renderBundle, format);
	}

	// GPU frame completion tracking
	private _gpuFrames = 0;
	private _gpuFpsTime = 0;
	private _gpuFps = 0;

	get gpuFps(): number { return this._gpuFps; }

	render(uniforms: Float32Array): void {
		this.device.queue.writeBuffer(this.uniformBuffer, 0, uniforms);

		const encoder = this.device.createCommandEncoder();
		const pass = encoder.beginRenderPass({
			colorAttachments: [{
				view: this.context.getCurrentTexture().createView(),
				loadOp: 'clear' as const,
				storeOp: 'store' as const,
				clearValue: { r: 0.04, g: 0.04, b: 0.04, a: 1 }
			}]
		});
		pass.executeBundles([this.renderBundle]);
		pass.end();
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
		this.uniformBuffer.destroy();
		this.device.destroy();
	}
}
