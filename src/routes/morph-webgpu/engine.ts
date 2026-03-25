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

		const pipeline = device.createRenderPipeline({
			layout: device.createPipelineLayout({ bindGroupLayouts: [bindGroupLayout] }),
			vertex: { module, entryPoint: 'vs' },
			fragment: {
				module,
				entryPoint: 'fs',
				targets: [{ format }]
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
	}

	destroy(): void {
		this.uniformBuffer.destroy();
		this.device.destroy();
	}
}
