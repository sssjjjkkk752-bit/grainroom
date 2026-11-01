// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import GrainroomSpectral

/// Owned by FilmRenderer's serial actor; all C ABI calls stay off the main actor.
final class SpectralSession {
    private let handle: UnsafeMutableRawPointer

    init(film: String, paper: String, params: String) throws {
        guard let directory = Bundle.main.url(forResource: "SpectralData", withExtension: nil) else {
            throw AppError.spectral("缺少光谱数据包，请重新安装应用。")
        }
        var pointer: UnsafeMutableRawPointer?
        var error = [CChar](repeating: 0, count: 2048)
        let status = directory.path.withCString { dir in
            film.withCString { film in
                paper.withCString { paper in
                    params.withCString { params in
                        gr_spectral_create(dir, film, paper, params, &pointer, &error, error.count)
                    }
                }
            }
        }
        guard status == 0, let pointer else { throw AppError.spectral(String(cString: error)) }
        handle = pointer
    }

    deinit { gr_spectral_destroy(handle) }

    func render(_ input: [Float], width: Int, height: Int, fullLongEdge: Int? = nil, seed: UInt64 = 0) throws -> [Float] {
        var output = [Float](repeating: 0, count: input.count)
        var error = [CChar](repeating: 0, count: 2048)
        if let fullLongEdge {
            let code = gr_spectral_tile_geometry(handle, UInt32(max(width,height)), UInt32(fullLongEdge), seed, &error, 2048)
            guard code == 0 else { throw AppError.spectral(String(cString:error)) }
        }
        let count = input.count
        let status = input.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                gr_spectral_render(handle, source.baseAddress, destination.baseAddress,
                                   UInt32(width), UInt32(height), count, &error, error.count)
            }
        }
        guard status == 0 else { throw AppError.spectral(String(cString: error)) }
        return output
    }
}
