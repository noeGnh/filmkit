package dev.noegnh.filmkit

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * `filmkit` method channel: `exportVideo` ({id, input, output, edit, lut}), `cancelExport`
 * ({id}), `getVideoInfo` ({path}), `getVideoFrame` ({path, positionMs, maxDimension}).
 * Progress goes back to Dart as `onProgress` ({id, progress}).
 */
class FilmkitPlugin :
    FlutterPlugin,
    MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private lateinit var executor: ExecutorService
    private val handler = Handler(Looper.getMainLooper())

    /** Running exports by id. Main thread only. */
    private val jobs = mutableMapOf<String, VideoExportJob>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        executor = Executors.newSingleThreadExecutor()
        channel = MethodChannel(binding.binaryMessenger, "filmkit")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        jobs.values.toList().forEach { it.cancel() }
        executor.shutdown()
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result
    ) {
        when (call.method) {
            "exportVideo" -> exportVideo(call, result)
            "cancelExport" -> {
                jobs[call.argument<String>("id")]?.cancel()
                result.success(null)
            }
            "getVideoInfo" -> getVideoInfo(call.argument<String>("path")!!, result)
            "getVideoFrame" -> getVideoFrame(call, result)
            else -> result.notImplemented()
        }
    }

    private fun exportVideo(
        call: MethodCall,
        result: Result
    ) {
        val id = call.argument<String>("id")!!
        val job =
            VideoExportJob(
                context = context,
                input = call.argument<String>("input")!!,
                output = call.argument<String>("output")!!,
                spec = EditSpec.fromMap(call.argument<Map<*, *>>("edit")!!),
                lut = Lut.fromMap(call.argument<Map<*, *>>("lut")),
                probeExecutor = executor,
                onProgress = { channel.invokeMethod("onProgress", mapOf("id" to id, "progress" to it)) },
                onDone = { outcome ->
                    jobs.remove(id)
                    outcome.fold(result::success) { result.reportError(it) }
                }
            )
        jobs[id] = job
        job.start()
    }

    private fun getVideoInfo(
        path: String,
        result: Result
    ) {
        executor.execute {
            val metadata = runCatching { VideoProbe.probe(path) }
            handler.post { metadata.fold({ result.success(it.toMap()) }) { result.reportError(it) } }
        }
    }

    private fun getVideoFrame(
        call: MethodCall,
        result: Result
    ) {
        val path = call.argument<String>("path")!!
        val positionMs = call.argument<Number>("positionMs")!!.toLong()
        val maxDimension = call.argument<Number>("maxDimension")?.toInt()
        executor.execute {
            val frame = runCatching { VideoFrames.frame(path, positionMs, maxDimension) }
            handler.post { frame.fold(result::success) { result.reportError(it) } }
        }
    }

    private fun Result.reportError(error: Throwable) {
        if (error is FilmkitError) {
            error(error.code, error.message, null)
        } else {
            error(FilmkitError.EXPORT_FAILED, error.toString(), null)
        }
    }
}
