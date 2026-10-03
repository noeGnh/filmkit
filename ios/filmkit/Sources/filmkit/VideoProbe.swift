import AVFoundation

struct VideoMetadata {
  /// Displayed size, rotation applied.
  let width: Int
  let height: Int
  let durationMs: Int64
  let hasAudio: Bool
  let isHdr: Bool

  var map: [String: Any] {
    ["width": width, "height": height, "durationMs": durationMs, "hasAudio": hasAudio, "isHdr": isHdr]
  }
}

enum VideoProbe {
  static func probe(_ asset: AVURLAsset) async throws -> VideoMetadata {
    let path = asset.url.path
    guard FileManager.default.fileExists(atPath: path) else { throw FilmkitError.invalidInput("File not found: \(path)") }
    do {
      guard let video = try await asset.loadTracks(withMediaType: .video).first else {
        throw FilmkitError.invalidInput("No video track in \(path)")
      }
      let (naturalSize, transform, characteristics) = try await video.load(.naturalSize, .preferredTransform, .mediaCharacteristics)
      let displayed = naturalSize.applying(transform)
      let duration = try await asset.load(.duration)
      let audio = try await asset.loadTracks(withMediaType: .audio)
      return VideoMetadata(
        width: Int(abs(displayed.width).rounded()),
        height: Int(abs(displayed.height).rounded()),
        durationMs: Int64((duration.seconds * 1000).rounded()),
        hasAudio: !audio.isEmpty,
        isHdr: characteristics.contains(.containsHDRVideo))
    } catch let error as FilmkitError {
      throw error
    } catch {
      throw FilmkitError.invalidInput("Can't read \(path): \(error.localizedDescription)")
    }
  }
}
