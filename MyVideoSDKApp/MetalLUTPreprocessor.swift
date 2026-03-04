import Foundation
import Metal
import ZoomVideoSDK

/// Applies a 3D color LUT (loaded from a .cube file) to raw YUV video frames using Metal.
final class MetalLUTPreprocessor: NSObject {

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let computePipeline: MTLComputePipelineState
    private let lutTexture: MTLTexture

    /// How strongly the LUT is applied. 0.0 = no effect, 1.0 = full LUT.
    var intensity: Float = 1.0

    /// Initialize with a .cube LUT file from the app bundle.
    /// - Parameter cubeName: Filename without extension (e.g. "MyLUT" for MyLUT.cube)
    init(cubeName: String) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue()
        else {
            fatalError("Metal not available")
        }

        self.device = device
        self.commandQueue = commandQueue

        // Load shader
        let library = device.makeDefaultLibrary()
        guard let kernel = library?.makeFunction(name: "apply_lut_yuv") else {
            fatalError("Failed to load apply_lut_yuv shader")
        }
        self.computePipeline = try! device.makeComputePipelineState(function: kernel)

        // Parse .cube file and create 3D texture
        guard let cubeURL = Bundle.main.url(forResource: cubeName, withExtension: "cube") else {
            fatalError("LUT file \(cubeName).cube not found in bundle")
        }
        let lut = MetalLUTPreprocessor.parseCubeFile(url: cubeURL)
        self.lutTexture = MetalLUTPreprocessor.create3DTexture(device: device, lut: lut)

        super.init()
    }

    // MARK: - Public API

    func process(rawData: ZoomVideoSDKPreProcessRawData) {
        let width = Int(rawData.size.width)
        let height = Int(rawData.size.height)
        let yStride = Int(rawData.yStride)
        let uStride = Int(rawData.uStride)
        let vStride = Int(rawData.vStride)

        guard let yPlane = malloc(yStride * height)?.assumingMemoryBound(to: UInt8.self),
              let uPlane = malloc(uStride * (height / 2))?.assumingMemoryBound(to: UInt8.self),
              let vPlane = malloc(vStride * (height / 2))?.assumingMemoryBound(to: UInt8.self)
        else { return }

        defer {
            free(yPlane)
            free(uPlane)
            free(vPlane)
        }

        // Copy in from Zoom buffers
        for line in 0..<height {
            guard let src = rawData.getYBuffer(Int32(line)) else { continue }
            memcpy(yPlane.advanced(by: line * yStride), src, yStride)
        }
        let chromaHeight = height / 2
        for line in 0..<chromaHeight {
            if let uSrc = rawData.getUBuffer(Int32(line)) {
                memcpy(uPlane.advanced(by: line * uStride), uSrc, uStride)
            }
            if let vSrc = rawData.getVBuffer(Int32(line)) {
                memcpy(vPlane.advanced(by: line * vStride), vSrc, vStride)
            }
        }

        // GPU processing
        processYUV(y: yPlane, u: uPlane, v: vPlane,
                   width: width, height: height,
                   yStride: yStride, uStride: uStride, vStride: vStride)

        // Copy back to Zoom buffers
        for line in 0..<height {
            guard let dst = rawData.getYBuffer(Int32(line)) else { continue }
            memcpy(dst, yPlane.advanced(by: line * yStride), yStride)
        }
        for line in 0..<chromaHeight {
            if let uDst = rawData.getUBuffer(Int32(line)) {
                memcpy(uDst, uPlane.advanced(by: line * uStride), uStride)
            }
            if let vDst = rawData.getVBuffer(Int32(line)) {
                memcpy(vDst, vPlane.advanced(by: line * vStride), vStride)
            }
        }
    }

    // MARK: - Metal Compute Dispatch

    private func processYUV(
        y: UnsafeMutablePointer<UInt8>,
        u: UnsafeMutablePointer<UInt8>,
        v: UnsafeMutablePointer<UInt8>,
        width: Int, height: Int,
        yStride: Int, uStride: Int, vStride: Int
    ) {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else { return }

        let yLength = yStride * height
        let uLength = uStride * (height / 2)
        let vLength = vStride * (height / 2)

        guard let yBuffer = device.makeBuffer(bytesNoCopy: y, length: yLength, options: .storageModeShared, deallocator: nil),
              let uBuffer = device.makeBuffer(bytesNoCopy: u, length: uLength, options: .storageModeShared, deallocator: nil),
              let vBuffer = device.makeBuffer(bytesNoCopy: v, length: vLength, options: .storageModeShared, deallocator: nil)
        else { return }

        let lutSize = lutTexture.width // cubic, so width == height == depth

        var params = LUTParamsSwift(
            width: UInt32(width),
            height: UInt32(height),
            yStride: UInt32(yStride),
            uStride: UInt32(uStride),
            vStride: UInt32(vStride),
            lutSize: UInt32(lutSize),
            intensity: intensity
        )

        guard let paramsBuffer = device.makeBuffer(bytes: &params, length: MemoryLayout<LUTParamsSwift>.stride, options: .storageModeShared) else { return }

        encoder.setComputePipelineState(computePipeline)
        encoder.setBuffer(yBuffer, offset: 0, index: 0)
        encoder.setBuffer(uBuffer, offset: 0, index: 1)
        encoder.setBuffer(vBuffer, offset: 0, index: 2)
        encoder.setBuffer(paramsBuffer, offset: 0, index: 3)
        encoder.setTexture(lutTexture, index: 0)

        let threadsPerThreadgroup = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroups = MTLSize(
            width:  (width  + 15) / 16,
            height: (height + 15) / 16,
            depth:  1
        )

        encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    // MARK: - .cube File Parser

    private struct LUTData {
        let size: Int
        let colors: [SIMD4<Float>] // RGBA, row-major order (R varies fastest)
    }

    /// Parses a standard .cube LUT file.
    /// Supports LUT_3D_SIZE, DOMAIN_MIN, DOMAIN_MAX, and comment lines starting with #.
    private static func parseCubeFile(url: URL) -> LUTData {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            fatalError("Cannot read LUT file at \(url.path)")
        }

        var size = 0
        var domainMin = SIMD3<Float>(0, 0, 0)
        var domainMax = SIMD3<Float>(1, 1, 1)
        var colors: [SIMD4<Float>] = []

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("TITLE") { continue }

            if trimmed.hasPrefix("LUT_3D_SIZE") {
                let parts = trimmed.split(separator: " ")
                if parts.count >= 2, let s = Int(parts[1]) { size = s }
                continue
            }
            if trimmed.hasPrefix("DOMAIN_MIN") {
                let parts = trimmed.split(separator: " ")
                if parts.count >= 4 {
                    domainMin = SIMD3<Float>(Float(parts[1])!, Float(parts[2])!, Float(parts[3])!)
                }
                continue
            }
            if trimmed.hasPrefix("DOMAIN_MAX") {
                let parts = trimmed.split(separator: " ")
                if parts.count >= 4 {
                    domainMax = SIMD3<Float>(Float(parts[1])!, Float(parts[2])!, Float(parts[3])!)
                }
                continue
            }

            // Data line: three floats
            let parts = trimmed.split(separator: " ")
            if parts.count >= 3,
               let r = Float(parts[0]),
               let g = Float(parts[1]),
               let b = Float(parts[2]) {
                // Remap from [domainMin, domainMax] to [0, 1]
                let range = domainMax - domainMin
                let rn = range.x > 0 ? (r - domainMin.x) / range.x : r
                let gn = range.y > 0 ? (g - domainMin.y) / range.y : g
                let bn = range.z > 0 ? (b - domainMin.z) / range.z : b
                colors.append(SIMD4<Float>(rn, gn, bn, 1.0))
            }
        }

        guard size > 0, colors.count == size * size * size else {
            fatalError("Invalid .cube file: expected \(size * size * size) entries, got \(colors.count)")
        }

        return LUTData(size: size, colors: colors)
    }

    /// Creates a 3D Metal texture from parsed LUT data.
    private static func create3DTexture(device: MTLDevice, lut: LUTData) -> MTLTexture {
        let desc = MTLTextureDescriptor()
        desc.textureType = .type3D
        desc.pixelFormat = .rgba32Float
        desc.width = lut.size
        desc.height = lut.size
        desc.depth = lut.size
        desc.usage = [.shaderRead]
        desc.storageMode = .shared

        guard let texture = device.makeTexture(descriptor: desc) else {
            fatalError("Failed to create 3D LUT texture")
        }

        // .cube ordering: R varies fastest, then G, then B
        // Metal 3D texture: region is (x=R, y=G, z=B)
        let bytesPerPixel = MemoryLayout<SIMD4<Float>>.stride  // 16 bytes
        let bytesPerRow = lut.size * bytesPerPixel
        let bytesPerImage = lut.size * bytesPerRow

        lut.colors.withUnsafeBufferPointer { ptr in
            texture.replace(
                region: MTLRegion(
                    origin: MTLOrigin(x: 0, y: 0, z: 0),
                    size: MTLSize(width: lut.size, height: lut.size, depth: lut.size)
                ),
                mipmapLevel: 0,
                slice: 0,
                withBytes: ptr.baseAddress!,
                bytesPerRow: bytesPerRow,
                bytesPerImage: bytesPerImage
            )
        }

        return texture
    }
}

// MARK: - Parameter Struct (must match LUTParams in LUT.metal)

private struct LUTParamsSwift {
    var width: UInt32
    var height: UInt32
    var yStride: UInt32
    var uStride: UInt32
    var vStride: UInt32
    var lutSize: UInt32
    var intensity: Float
}
