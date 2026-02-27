import Foundation
import Metal
import CoreVideo
import ZoomVideoSDK

final class MetalRedPreprocessor: NSObject {

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let computePipeline: MTLComputePipelineState

    override init() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue()
        else {
            fatalError("Metal not available")
        }

        self.device = device
        self.commandQueue = commandQueue

        let library = device.makeDefaultLibrary()
        guard let kernel = library?.makeFunction(name: "tint_red_yuv") else {
            fatalError("Failed to load tint_red_yuv shader")
        }
        self.computePipeline = try! device.makeComputePipelineState(function: kernel)
        
        super.init()
    }

    // Entry point from Zoom preprocessor
    
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

        processYUV(
            y: yPlane,
            u: uPlane,
            v: vPlane,
            width: width,
            height: height,
            yStride: yStride,
            uStride: uStride,
            vStride: vStride
        )
        
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

    // MARK: - Internal Metal compute for YUV

    private func processYUV(
        y: UnsafeMutablePointer<UInt8>,
        u: UnsafeMutablePointer<UInt8>,
        v: UnsafeMutablePointer<UInt8>,
        width: Int,
        height: Int,
        yStride: Int,
        uStride: Int,
        vStride: Int
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

        var params = YUVParamsSwift(
            width: UInt32(width),
            height: UInt32(height),
            yStride: UInt32(yStride),
            uStride: UInt32(uStride),
            vStride: UInt32(vStride),
            mixFactor: 0.5,   // 50% red
            uRed: 90.0,
            vRed: 240.0
        )

        guard let paramsBuffer = device.makeBuffer(bytes: &params, length: MemoryLayout<YUVParamsSwift>.stride, options: .storageModeShared) else { return }

        encoder.setComputePipelineState(computePipeline)
        encoder.setBuffer(yBuffer, offset: 0, index: 0)
        encoder.setBuffer(uBuffer, offset: 0, index: 1)
        encoder.setBuffer(vBuffer, offset: 0, index: 2)
        encoder.setBuffer(paramsBuffer, offset: 0, index: 3)

        let threadsPerThreadgroup = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroups = MTLSize(
            width:  (width  + threadsPerThreadgroup.width  - 1) / threadsPerThreadgroup.width,
            height: (height + threadsPerThreadgroup.height - 1) / threadsPerThreadgroup.height,
            depth:  1
        )

        encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
}

private struct YUVParamsSwift {
    var width: UInt32
    var height: UInt32
    var yStride: UInt32
    var uStride: UInt32
    var vStride: UInt32
    var mixFactor: Float
    var uRed: Float
    var vRed: Float
}
