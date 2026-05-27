package com.xyern.yanji

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.nio.ByteBuffer
import java.nio.ByteOrder

class AudioCapturerPlugin : FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler {
    private lateinit var channel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var audioRecord: AudioRecord? = null
    private var isRecording = false
    private var recordingThread: Thread? = null
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    companion object {
        private const val AUDIO_SOURCE = MediaRecorder.AudioSource.MIC
        private const val SAMPLE_RATE = 16000
        private const val CHANNEL_CONFIG = AudioFormat.CHANNEL_IN_MONO
        private const val AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT
        private const val BUFFER_SIZE = 3200 // 100ms of 16kHz 16-bit mono audio
    }

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "meeting_note/audio_capturer")
        channel.setMethodCallHandler(this)
        
        eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "meeting_note/audio_stream")
        eventChannel.setStreamHandler(this)
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "startRecording" -> startRecording(result)
            "stopRecording" -> stopRecording(result)
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun startRecording(result: Result) {
        if (isRecording) {
            result.success(null)
            return
        }

        try {
            val minBufferSize = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL_CONFIG, AUDIO_FORMAT)
            audioRecord = AudioRecord(
                AUDIO_SOURCE,
                SAMPLE_RATE,
                CHANNEL_CONFIG,
                AUDIO_FORMAT,
                minBufferSize
            )

            audioRecord?.startRecording()
            isRecording = true

            // Start recording thread
            recordingThread = Thread {
                recordAudio()
            }
            recordingThread?.start()

            result.success(null)
        } catch (e: Exception) {
            result.error("RECORDING_ERROR", "Failed to start recording: ${e.message}", null)
        }
    }

    private fun stopRecording(result: Result) {
        if (!isRecording) {
            result.success(null)
            return
        }

        try {
            isRecording = false
            recordingThread?.join()

            audioRecord?.stop()
            audioRecord?.release()
            audioRecord = null

            result.success(null)
        } catch (e: Exception) {
            result.error("STOP_ERROR", "Failed to stop recording: ${e.message}", null)
        }
    }

    private fun recordAudio() {
        val buffer = ShortArray(BUFFER_SIZE / 2) // 16-bit samples

        while (isRecording) {
            val read = audioRecord?.read(buffer, 0, buffer.size) ?: 0
            if (read > 0) {
                // Convert short array to byte array (little-endian)
                val byteArray = ShortArrayToByteArray(buffer, read)
                
                // Send audio data to Flutter on the main thread
                mainHandler.post {
                    eventSink?.success(byteArray)
                }
            }
        }
    }

    private fun ShortArrayToByteArray(shortArray: ShortArray, length: Int): ByteArray {
        val buffer = ByteBuffer.allocate(length * 2)
        buffer.order(ByteOrder.LITTLE_ENDIAN)
        for (i in 0 until length) {
            buffer.putShort(shortArray[i])
        }
        return buffer.array()
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }
}