package dev.noegnh.filmkit

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapRegionDecoder
import android.graphics.ColorSpace
import android.graphics.Matrix
import android.graphics.Rect
import android.os.Build
import androidx.exifinterface.media.ExifInterface
import java.io.File
import java.io.IOException
import java.util.stream.IntStream
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** Photo export: decode (only the cropped region, subsampled), orient, scale, LUT, JPEG. */
internal object ImageExporter {
    /** Blocking: call it off the main thread. */
    fun export(
        input: String,
        output: String,
        spec: EditSpec,
        lut: Lut?,
        quality: Int,
        keepLocation: Boolean
    ): Map<String, Any> {
        if (!File(input).isFile) throw FilmkitError(FilmkitError.INVALID_INPUT, "File not found: $input")
        val sourceExif =
            try {
                ExifInterface(input)
            } catch (e: IOException) {
                null
            }
        val orientation = sourceExif?.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL) ?: ExifInterface.ORIENTATION_NORMAL

        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(input, bounds)
        val storedWidth = bounds.outWidth
        val storedHeight = bounds.outHeight
        if (storedWidth <= 0 || storedHeight <= 0) throw FilmkitError(FilmkitError.INVALID_INPUT, "Not a supported image: $input")

        val transposed = ExifOrientation.isTransposed(orientation)
        val size =
            ExportGeometry.imageOutputSize(
                if (transposed) storedHeight else storedWidth,
                if (transposed) storedWidth else storedHeight,
                spec.crop,
                spec.maxDimension
            )
        // Output size in the stored orientation.
        val storedOutWidth = if (transposed) size.height else size.width
        val storedOutHeight = if (transposed) size.width else size.height

        val crop = ExifOrientation.displayedToStored(orientation, spec.crop)
        val region =
            Rect(
                (crop.left * storedWidth).roundToInt(),
                (crop.top * storedHeight).roundToInt(),
                (crop.right * storedWidth).roundToInt(),
                (crop.bottom * storedHeight).roundToInt()
            )
        if (region.isEmpty) region.set(region.left, region.top, max(region.right, region.left + 1), max(region.bottom, region.top + 1))

        // Decode at the smallest power-of-2 subsampling that keeps at least the output size.
        var sample = 1
        while (region.width() / (sample * 2) >= storedOutWidth && region.height() / (sample * 2) >= storedOutHeight) sample *= 2
        val decoded = decodeRegion(input, region, sample)

        val matrix =
            Matrix().apply {
                postScale(storedOutWidth.toFloat() / decoded.width, storedOutHeight.toFloat() / decoded.height)
                postRotate(ExifOrientation.rotationDegrees(orientation).toFloat())
                if (ExifOrientation.isFlipped(orientation)) postScale(-1f, 1f)
            }
        var bitmap = Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true)
        if (bitmap.width != size.width || bitmap.height != size.height) bitmap = Bitmap.createScaledBitmap(bitmap, size.width, size.height, true)
        if (!bitmap.isMutable || bitmap.config != Bitmap.Config.ARGB_8888) bitmap = bitmap.copy(Bitmap.Config.ARGB_8888, true)
        if (lut != null) applyLut(bitmap, lut)

        File(output).parentFile?.mkdirs()
        File(output).outputStream().use { stream ->
            if (!bitmap.compress(Bitmap.CompressFormat.JPEG, quality, stream)) throw FilmkitError(FilmkitError.EXPORT_FAILED, "JPEG encoding failed")
        }
        writeMetadata(sourceExif, output, keepLocation)
        return mapOf("path" to output, "width" to size.width, "height" to size.height)
    }

    private fun decodeRegion(
        input: String,
        region: Rect,
        sample: Int
    ): Bitmap {
        val options =
            BitmapFactory.Options().apply {
                inSampleSize = sample
                inPreferredConfig = Bitmap.Config.ARGB_8888
                // Wide-gamut photos are converted to sRGB, as the preview and the output.
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) inPreferredColorSpace = ColorSpace.get(ColorSpace.Named.SRGB)
            }
        val decoder =
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    BitmapRegionDecoder.newInstance(input)
                } else {
                    @Suppress("DEPRECATION")
                    BitmapRegionDecoder.newInstance(input, false)
                }
            } catch (e: IOException) {
                null
            }
        if (decoder != null) {
            try {
                decoder.decodeRegion(region, options)?.let { return it }
            } finally {
                decoder.recycle()
            }
        }
        // Formats without region decoding: decode the whole image, then crop.
        val full = BitmapFactory.decodeFile(input, options) ?: throw FilmkitError(FilmkitError.INVALID_INPUT, "Can't decode $input")
        val left = min(region.left / sample, full.width - 1)
        val top = min(region.top / sample, full.height - 1)
        return Bitmap.createBitmap(full, left, top, max(1, min(region.width() / sample, full.width - left)), max(1, min(region.height() / sample, full.height - top)))
    }

    private fun applyLut(
        bitmap: Bitmap,
        lut: Lut
    ) {
        val width = bitmap.width
        val height = bitmap.height
        val pixels = IntArray(width * height)
        // Non-premultiplied ARGB.
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height)
        IntStream.range(0, height).parallel().forEach { y ->
            val rgb = FloatArray(3)
            for (i in y * width until (y + 1) * width) {
                val p = pixels[i]
                rgb[0] = ((p shr 16) and 0xFF) / 255f
                rgb[1] = ((p shr 8) and 0xFF) / 255f
                rgb[2] = (p and 0xFF) / 255f
                lut.apply(rgb)
                pixels[i] = (p and 0xFF000000.toInt()) or
                    ((rgb[0] * 255).roundToInt() shl 16) or
                    ((rgb[1] * 255).roundToInt() shl 8) or
                    (rgb[2] * 255).roundToInt()
            }
        }
        bitmap.setPixels(pixels, 0, width, 0, 0, width, height)
    }

    /** Copies the capture metadata of the source; the pixels are already oriented. */
    private fun writeMetadata(
        source: ExifInterface?,
        output: String,
        keepLocation: Boolean
    ) {
        val exif = ExifInterface(output)
        if (source != null) {
            for (tag in if (keepLocation) CAPTURE_TAGS + LOCATION_TAGS else CAPTURE_TAGS) {
                source.getAttribute(tag)?.let { exif.setAttribute(tag, it) }
            }
        }
        exif.setAttribute(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL.toString())
        exif.saveAttributes()
    }

    private val CAPTURE_TAGS =
        listOf(
            ExifInterface.TAG_DATETIME,
            ExifInterface.TAG_DATETIME_ORIGINAL,
            ExifInterface.TAG_DATETIME_DIGITIZED,
            ExifInterface.TAG_OFFSET_TIME,
            ExifInterface.TAG_OFFSET_TIME_ORIGINAL,
            ExifInterface.TAG_OFFSET_TIME_DIGITIZED,
            ExifInterface.TAG_SUBSEC_TIME,
            ExifInterface.TAG_SUBSEC_TIME_ORIGINAL,
            ExifInterface.TAG_SUBSEC_TIME_DIGITIZED,
            ExifInterface.TAG_MAKE,
            ExifInterface.TAG_MODEL,
            ExifInterface.TAG_LENS_MAKE,
            ExifInterface.TAG_LENS_MODEL,
            ExifInterface.TAG_ARTIST,
            ExifInterface.TAG_COPYRIGHT,
            ExifInterface.TAG_IMAGE_DESCRIPTION,
            ExifInterface.TAG_EXPOSURE_TIME,
            ExifInterface.TAG_F_NUMBER,
            ExifInterface.TAG_PHOTOGRAPHIC_SENSITIVITY,
            ExifInterface.TAG_EXPOSURE_PROGRAM,
            ExifInterface.TAG_EXPOSURE_BIAS_VALUE,
            ExifInterface.TAG_METERING_MODE,
            ExifInterface.TAG_FLASH,
            ExifInterface.TAG_FOCAL_LENGTH,
            ExifInterface.TAG_FOCAL_LENGTH_IN_35MM_FILM,
            ExifInterface.TAG_WHITE_BALANCE
        )

    private val LOCATION_TAGS =
        listOf(
            ExifInterface.TAG_GPS_VERSION_ID,
            ExifInterface.TAG_GPS_LATITUDE,
            ExifInterface.TAG_GPS_LATITUDE_REF,
            ExifInterface.TAG_GPS_LONGITUDE,
            ExifInterface.TAG_GPS_LONGITUDE_REF,
            ExifInterface.TAG_GPS_ALTITUDE,
            ExifInterface.TAG_GPS_ALTITUDE_REF,
            ExifInterface.TAG_GPS_TIMESTAMP,
            ExifInterface.TAG_GPS_DATESTAMP,
            ExifInterface.TAG_GPS_MAP_DATUM,
            ExifInterface.TAG_GPS_IMG_DIRECTION,
            ExifInterface.TAG_GPS_IMG_DIRECTION_REF,
            ExifInterface.TAG_GPS_SPEED,
            ExifInterface.TAG_GPS_SPEED_REF,
            ExifInterface.TAG_GPS_H_POSITIONING_ERROR,
            ExifInterface.TAG_GPS_PROCESSING_METHOD
        )
}
