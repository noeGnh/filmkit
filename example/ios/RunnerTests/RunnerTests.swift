import XCTest

@testable import filmkit

class ExportGeometryTests: XCTestCase {
  func testOutputSizeKeepsTheSourceSizeWithoutCropOrLimit() {
    let size = ExportGeometry.outputSize(displayWidth: 640, displayHeight: 360, crop: .full, maxDimension: nil)
    XCTAssertEqual(size.width, 640)
    XCTAssertEqual(size.height, 360)
  }

  func testOutputSizeAppliesTheCropThenTheLimit() {
    let crop = CropRect(left: 0.25, top: 0, right: 1, bottom: 0.75)
    let small = ExportGeometry.outputSize(displayWidth: 640, displayHeight: 360, crop: crop, maxDimension: 1080)
    XCTAssertEqual([small.width, small.height], [480, 270])
    let large = ExportGeometry.outputSize(displayWidth: 3840, displayHeight: 2160, crop: crop, maxDimension: 1080)
    XCTAssertEqual([large.width, large.height], [1080, 608])
  }

  func testOutputSizeNeverScalesUpAndRoundsToEvenValues() {
    let up = ExportGeometry.outputSize(displayWidth: 640, displayHeight: 360, crop: .full, maxDimension: 4000)
    XCTAssertEqual([up.width, up.height], [640, 360])
    let odd = ExportGeometry.outputSize(displayWidth: 641, displayHeight: 359, crop: .full, maxDimension: nil)
    XCTAssertEqual([odd.width, odd.height], [642, 360])
  }

  func testCoreImageRectHasItsOriginAtTheBottomLeft() {
    let rect = ExportGeometry.coreImageRect(
      displayWidth: 640, displayHeight: 360, crop: CropRect(left: 0.25, top: 0, right: 1, bottom: 0.75))
    XCTAssertEqual(rect, CGRect(x: 160, y: 90, width: 480, height: 270))
  }

  func testEditSpecParsesTheDartJson() {
    let spec = EditSpec(map: [
      "trimStartMs": NSNumber(value: 1000), "trimEndMs": NSNumber(value: 4000),
      "crop": [0.25, 0, 1, 0.75].map { NSNumber(value: $0) }, "maxDimension": NSNumber(value: 1080),
    ])
    XCTAssertEqual(
      spec, EditSpec(trimStartMs: 1000, trimEndMs: 4000, crop: CropRect(left: 0.25, top: 0, right: 1, bottom: 0.75), maxDimension: 1080))
    let defaults = EditSpec(map: ["trimStartMs": NSNumber(value: 0), "trimEndMs": NSNull(), "crop": NSNull(), "maxDimension": NSNull()])
    XCTAssertEqual(defaults, EditSpec(trimStartMs: 0, trimEndMs: nil, crop: .full, maxDimension: nil))
  }

  func testLutCubeDataIsRgbaWithRedVaryingFastest() {
    let lut = Lut(size: 2, data: (0..<24).map { Float($0) / 23 })
    let cube = lut.cubeData.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    XCTAssertEqual(cube.count, 32)
    // Entries keep their order; an alpha of 1 is added after each RGB triplet.
    let expected: [Float] = [0, 1, 2].map { Float($0) / 23 } + [1] + [3, 4, 5].map { Float($0) / 23 } + [1]
    XCTAssertEqual(Array(cube[0..<8]), expected)
    XCTAssertEqual(cube[31], 1)
    XCTAssertEqual(cube[30], 23 / 23)
  }
}
