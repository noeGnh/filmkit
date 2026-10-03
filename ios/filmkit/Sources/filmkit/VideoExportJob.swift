import AVFoundation
import CoreImage

/// One export with `AVAssetExportSession`. Main actor only; `onProgress` and the completion
/// are called on the main actor, the completion exactly once.
final class VideoExportJob {
  private let input: URL
  private let output: URL
  private let spec: EditSpec
  private let onProgress: (Double) -> Void
  private var task: Task<Void, Never>?
  private var session: AVAssetExportSession?
  private var cancelled = false

  init(input: URL, output: URL, spec: EditSpec, onProgress: @escaping (Double) -> Void) {
    self.input = input
    self.output = output
    self.spec = spec
    self.onProgress = onProgress
  }

  func start(completion: @escaping (Result<[String: Any], Error>) -> Void) {
    task = Task { @MainActor in
      let result: Result<[String: Any], Error>
      do {
        result = .success(try await export())
      } catch {
        result = .failure(cancelled ? FilmkitError.cancelled : error)
      }
      if cancelled { try? FileManager.default.removeItem(at: output) }
      completion(result)
    }
  }

  /// Stops the export and deletes the partial output.
  func cancel() {
    cancelled = true
    session?.cancelExport()
    task?.cancel()
  }

  @MainActor
  private func export() async throws -> [String: Any] {
    let asset = AVURLAsset(url: input)
    let metadata = try await VideoProbe.probe(asset)
    guard spec.trimStartMs < metadata.durationMs else {
      throw FilmkitError.invalidInput("trimStart (\(spec.trimStartMs) ms) is after the end of the video (\(metadata.durationMs) ms)")
    }
    if cancelled { throw FilmkitError.cancelled }

    let size = ExportGeometry.outputSize(
      displayWidth: metadata.width, displayHeight: metadata.height, crop: spec.crop, maxDimension: spec.maxDimension)
    let cropRect = ExportGeometry.coreImageRect(displayWidth: metadata.width, displayHeight: metadata.height, crop: spec.crop)
    let scaleX = CGFloat(size.width) / cropRect.width
    let scaleY = CGFloat(size.height) / cropRect.height
    // Frames arrive in displayed orientation; the output has its pixels rotated (no rotation tag).
    let handler: @Sendable (AVAsynchronousCIImageFilteringRequest) -> Void = { request in
      let image = request.sourceImage
        .cropped(to: cropRect)
        .transformed(by: CGAffineTransform(translationX: -cropRect.minX, y: -cropRect.minY))
        .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
      request.finish(with: image, context: nil)
    }
    let composition: AVMutableVideoComposition
    if #available(iOS 16.0, *) {
      composition = try await AVMutableVideoComposition.videoComposition(with: asset, applyingCIFiltersWithHandler: handler)
    } else {
      composition = AVMutableVideoComposition(asset: asset, applyingCIFiltersWithHandler: handler)
    }
    composition.renderSize = CGSize(width: size.width, height: size.height)
    // SDR output: HDR sources are tone mapped.
    composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
    composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
    composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2

    guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
      throw FilmkitError.exportFailed("No export session for \(input.path)")
    }
    session.videoComposition = composition
    let endMs = min(spec.trimEndMs ?? metadata.durationMs, metadata.durationMs)
    session.timeRange = CMTimeRange(
      start: CMTime(value: spec.trimStartMs, timescale: 1000), end: CMTime(value: endMs, timescale: 1000))
    self.session = session

    try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? FileManager.default.removeItem(at: output)
    if cancelled { throw FilmkitError.cancelled }

    let progress = Task { @MainActor [onProgress] in
      while !Task.isCancelled {
        onProgress(Double(session.progress))
        try? await Task.sleep(nanoseconds: 100_000_000)
      }
    }
    defer { progress.cancel() }

    if #available(iOS 18.0, *) {
      do {
        try await session.export(to: output, as: .mp4)
      } catch {
        throw cancelled ? FilmkitError.cancelled : FilmkitError.exportFailed("\(error)")
      }
    } else {
      session.outputURL = output
      session.outputFileType = .mp4
      await session.export()
      if session.status == .cancelled { throw FilmkitError.cancelled }
      if let error = session.error { throw FilmkitError.exportFailed("\(error)") }
    }
    return ["path": output.path, "width": size.width, "height": size.height]
  }
}
