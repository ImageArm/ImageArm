import Foundation
import Metal
import CoreImage
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// GPU-accelerated image processing using Metal compute shaders and Core Image.
/// Marqué `@unchecked Sendable` car toutes les propriétés sont initialisées une seule fois
/// dans `init()` et les méthodes publiques n'écrivent dans aucune propriété d'instance —
/// elles n'utilisent que des variables locales et les objets Metal/CIContext (thread-safe).
final class GPUProcessor: @unchecked Sendable {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let ciContext: CIContext
    private let quantizePipeline: MTLComputePipelineState
    private let medianCutPipeline: MTLComputePipelineState

    static let shared: GPUProcessor? = {
        try? GPUProcessor()
    }()

    private init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw GPUError.noDevice
        }
        guard let queue = device.makeCommandQueue() else {
            throw GPUError.noCommandQueue
        }
        self.device = device
        self.commandQueue = queue
        self.ciContext = CIContext(mtlDevice: device, options: [
            .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
            .highQualityDownsample: true,
        ])

        // Compile Metal shaders at runtime
        let library = try device.makeLibrary(source: Self.metalShaderSource, options: nil)

        guard let quantizeFunc = library.makeFunction(name: "quantize_dither"),
              let medianCutFunc = library.makeFunction(name: "build_histogram") else {
            throw GPUError.shaderCompilationFailed
        }
        self.quantizePipeline = try device.makeComputePipelineState(function: quantizeFunc)
        self.medianCutPipeline = try device.makeComputePipelineState(function: medianCutFunc)
    }

    enum GPUError: Error {
        case noDevice, noCommandQueue, shaderCompilationFailed
        case textureCreationFailed, processingFailed
    }

    // MARK: - PNG Lossy Quantization (GPU-accelerated)

    /// Dimension maximale pour éviter les bombes de décompression (OOM/crash)
    private static let maxTextureDimension = 16384

    /// Quantize PNG colors using GPU dithering, similar to pngquant but Metal-accelerated
    func quantizePNG(inputPath: String, outputPath: String, quality: Int) throws {
        guard let cgImage = loadCGImage(from: inputPath) else {
            throw GPUError.processingFailed
        }

        let width = cgImage.width
        let height = cgImage.height

        // Guard against decompression bombs — reject images exceeding Metal texture limits
        guard width > 0, height > 0,
              width <= Self.maxTextureDimension, height <= Self.maxTextureDimension else {
            throw GPUError.processingFailed
        }

        // Create input texture
        let textureDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        textureDesc.usage = [.shaderRead]
        guard let inputTexture = device.makeTexture(descriptor: textureDesc) else {
            throw GPUError.textureCreationFailed
        }

        // Upload image data to texture
        let bytesPerRow = 4 * width
        var pixelData = [UInt8](repeating: 0, count: bytesPerRow * height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw GPUError.processingFailed }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        inputTexture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: pixelData,
            bytesPerRow: bytesPerRow
        )

        // Create output texture
        let outDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        outDesc.usage = [.shaderWrite, .shaderRead]
        guard let outputTexture = device.makeTexture(descriptor: outDesc) else {
            throw GPUError.textureCreationFailed
        }

        // Params buffer: number of color levels per channel based on quality
        let levels = max(4, min(256, quality * 256 / 100))
        var params = QuantizeParams(
            colorLevels: UInt32(levels),
            ditherStrength: quality < 70 ? 1.5 : (quality < 85 ? 1.0 : 0.5),
            width: UInt32(width),
            height: UInt32(height)
        )
        guard let paramsBuffer = device.makeBuffer(
            bytes: &params,
            length: MemoryLayout<QuantizeParams>.size,
            options: .storageModeShared
        ) else { throw GPUError.processingFailed }

        // Dispatch compute
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw GPUError.processingFailed
        }

        encoder.setComputePipelineState(quantizePipeline)
        encoder.setTexture(inputTexture, index: 0)
        encoder.setTexture(outputTexture, index: 1)
        encoder.setBuffer(paramsBuffer, offset: 0, index: 0)

        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadGroups = MTLSize(
            width: (width + 15) / 16,
            height: (height + 15) / 16,
            depth: 1
        )
        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        // Read back result
        var outputData = [UInt8](repeating: 0, count: bytesPerRow * height)
        outputTexture.getBytes(
            &outputData,
            bytesPerRow: bytesPerRow,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )

        // Write PNG with ImageIO
        guard let outContext = CGContext(
            data: &outputData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ),
        let outImage = outContext.makeImage() else {
            throw GPUError.processingFailed
        }

        let url = URL(fileURLWithPath: outputPath)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw GPUError.processingFailed
        }
        CGImageDestinationAddImage(dest, outImage, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw GPUError.processingFailed
        }
    }

    // MARK: - JPEG Hardware Encoding

    /// Encode JPEG using Apple Silicon hardware encoder via ImageIO
    func encodeJPEGHardware(inputPath: String, outputPath: String, quality: Int, stripMetadata: Bool) throws {
        guard let cgImage = loadCGImage(from: inputPath) else {
            throw GPUError.processingFailed
        }

        // Guard against decompression bombs
        guard cgImage.width > 0, cgImage.height > 0,
              cgImage.width <= Self.maxTextureDimension, cgImage.height <= Self.maxTextureDimension else {
            throw GPUError.processingFailed
        }

        let url = URL(fileURLWithPath: outputPath)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw GPUError.processingFailed
        }

        var options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: Float(quality) / 100.0,
            kCGImageDestinationOptimizeColorForSharing: true,
        ]

        if !stripMetadata,
           let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: inputPath) as CFURL, nil),
           let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            // Preserve original metadata
            for (key, value) in metadata {
                options[key] = value
            }
        }

        CGImageDestinationAddImage(dest, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw GPUError.processingFailed
        }
    }

    func encodeHEIFHardware(inputPath: String, outputPath: String, quality: Int, stripMetadata: Bool) throws {
        guard let cgImage = loadCGImage(from: inputPath) else {
            throw GPUError.processingFailed
        }

        guard cgImage.width > 0, cgImage.height > 0,
              cgImage.width <= Self.maxTextureDimension, cgImage.height <= Self.maxTextureDimension else {
            throw GPUError.processingFailed
        }

        let url = URL(fileURLWithPath: outputPath)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.heic.identifier as CFString, 1, nil) else {
            throw GPUError.processingFailed
        }

        var options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: Float(quality) / 100.0,
            kCGImageDestinationOptimizeColorForSharing: true,
        ]

        if !stripMetadata,
           let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: inputPath) as CFURL, nil),
           let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            for (key, value) in metadata {
                options[key] = value
            }
        }

        CGImageDestinationAddImage(dest, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw GPUError.processingFailed
        }
    }

    /// Encode HEIF at maximum quality (quality=1.0). Note: HEIC via ImageIO does not
    /// support true lossless encoding — this is highest-quality lossy compression.
    func encodeHEIFMaxQuality(inputPath: String, outputPath: String, stripMetadata: Bool) throws {
        guard let cgImage = loadCGImage(from: inputPath) else {
            throw GPUError.processingFailed
        }

        guard cgImage.width > 0, cgImage.height > 0,
              cgImage.width <= Self.maxTextureDimension, cgImage.height <= Self.maxTextureDimension else {
            throw GPUError.processingFailed
        }

        let url = URL(fileURLWithPath: outputPath)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.heic.identifier as CFString, 1, nil) else {
            throw GPUError.processingFailed
        }

        var options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 1.0 as Float,
        ]

        if !stripMetadata,
           let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: inputPath) as CFURL, nil),
           let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            for (key, value) in metadata {
                options[key] = value
            }
        }

        CGImageDestinationAddImage(dest, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw GPUError.processingFailed
        }
    }

    // MARK: - AVIF Hardware Encoding (macOS 14+)

    private static let avifUTI = "public.avif"

    func encodeAVIFHardware(inputPath: String, outputPath: String, quality: Int, stripMetadata: Bool) throws {
        guard let cgImage = loadCGImage(from: inputPath) else {
            throw GPUError.processingFailed
        }

        guard cgImage.width > 0, cgImage.height > 0,
              cgImage.width <= Self.maxTextureDimension, cgImage.height <= Self.maxTextureDimension else {
            throw GPUError.processingFailed
        }

        let url = URL(fileURLWithPath: outputPath)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, Self.avifUTI as CFString, 1, nil) else {
            throw GPUError.processingFailed
        }

        var options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: Float(quality) / 100.0,
        ]

        if !stripMetadata,
           let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: inputPath) as CFURL, nil),
           let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            for (key, value) in metadata {
                options[key] = value
            }
        }

        CGImageDestinationAddImage(dest, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw GPUError.processingFailed
        }
    }

    func encodeAVIFMaxQuality(inputPath: String, outputPath: String, stripMetadata: Bool) throws {
        // quality=95 (0.95) évite le code path lossless de ImageIO qui échoue sur macOS 14
        try encodeAVIFHardware(inputPath: inputPath, outputPath: outputPath, quality: 95, stripMetadata: stripMetadata)
    }

    // MARK: - Helpers

    private func loadCGImage(from path: String) -> CGImage? {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [
                kCGImageSourceShouldCache: false,
                kCGImageSourceShouldAllowFloat: true,
              ] as CFDictionary) else {
            return nil
        }
        return image
    }

    // MARK: - Metal Shader Source

    private struct QuantizeParams {
        var colorLevels: UInt32
        var ditherStrength: Float
        var width: UInt32
        var height: UInt32
    }

    private static let metalShaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct QuantizeParams {
        uint colorLevels;
        float ditherStrength;
        uint width;
        uint height;
    };

    // 8x8 Bayer dithering matrix
    constant float bayerMatrix[64] = {
         0.0/64.0, 32.0/64.0,  8.0/64.0, 40.0/64.0,  2.0/64.0, 34.0/64.0, 10.0/64.0, 42.0/64.0,
        48.0/64.0, 16.0/64.0, 56.0/64.0, 24.0/64.0, 50.0/64.0, 18.0/64.0, 58.0/64.0, 26.0/64.0,
        12.0/64.0, 44.0/64.0,  4.0/64.0, 36.0/64.0, 14.0/64.0, 46.0/64.0,  6.0/64.0, 38.0/64.0,
        60.0/64.0, 28.0/64.0, 52.0/64.0, 20.0/64.0, 62.0/64.0, 30.0/64.0, 54.0/64.0, 22.0/64.0,
         3.0/64.0, 35.0/64.0, 11.0/64.0, 43.0/64.0,  1.0/64.0, 33.0/64.0,  9.0/64.0, 41.0/64.0,
        51.0/64.0, 19.0/64.0, 59.0/64.0, 27.0/64.0, 49.0/64.0, 17.0/64.0, 57.0/64.0, 25.0/64.0,
        15.0/64.0, 47.0/64.0,  7.0/64.0, 39.0/64.0, 13.0/64.0, 45.0/64.0,  5.0/64.0, 37.0/64.0,
        63.0/64.0, 31.0/64.0, 55.0/64.0, 23.0/64.0, 61.0/64.0, 29.0/64.0, 53.0/64.0, 21.0/64.0
    };

    // Blue noise hash for higher quality dithering
    float blueNoise(uint2 pos, uint seed) {
        uint h = (pos.x * 73856093u) ^ (pos.y * 19349663u) ^ (seed * 83492791u);
        h = h * 2654435761u;
        h ^= h >> 16;
        return float(h & 0xFFFFu) / 65535.0;
    }

    kernel void quantize_dither(
        texture2d<float, access::read> input [[texture(0)]],
        texture2d<float, access::write> output [[texture(1)]],
        constant QuantizeParams& params [[buffer(0)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= params.width || gid.y >= params.height) return;

        float4 color = input.read(gid);

        // Bayer dithering
        uint bx = gid.x % 8;
        uint by = gid.y % 8;
        float bayerValue = bayerMatrix[by * 8 + bx] - 0.5;

        // Blue noise component for less patterned result
        float noise = blueNoise(gid, 42) - 0.5;

        // Mix Bayer and blue noise
        float dither = mix(bayerValue, noise, 0.4) * params.ditherStrength;

        float levels = float(params.colorLevels - 1);
        float invLevels = 1.0 / levels;

        // Un-premultiply alpha before quantizing for correct color handling
        float3 rgb = color.a > 0.001 ? color.rgb / color.a : color.rgb;
        rgb = rgb + dither * invLevels;
        rgb = clamp(rgb, 0.0, 1.0);
        rgb = round(rgb * levels) * invLevels;
        // Re-premultiply
        rgb = rgb * color.a;

        output.write(float4(rgb, color.a), gid);
    }

    // Histogram builder for potential future median-cut quantization
    struct HistogramEntry {
        atomic_uint count;
    };

    kernel void build_histogram(
        texture2d<float, access::read> input [[texture(0)]],
        device HistogramEntry* histogram [[buffer(0)]],
        constant QuantizeParams& params [[buffer(1)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= params.width || gid.y >= params.height) return;

        float4 color = input.read(gid);
        // 5-bit per channel histogram (32x32x32 = 32768 entries)
        uint r = uint(color.r * 31.0);
        uint g = uint(color.g * 31.0);
        uint b = uint(color.b * 31.0);
        uint idx = (r << 10) | (g << 5) | b;
        atomic_fetch_add_explicit(&histogram[idx].count, 1, memory_order_relaxed);
    }
    """
}
