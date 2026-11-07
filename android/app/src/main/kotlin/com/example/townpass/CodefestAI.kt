// SPDX-License-Identifier: AGPL-3.0-or-later
package com.example.townpass

import android.Manifest
import android.content.ComponentName
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Conversation
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.SamplerConfig
import com.google.ai.edge.litertlm.RepetitionPenaltyConfig
import com.google.ai.edge.litertlm.NoRepeatNgramConfig
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class CodefestAI(private val activity: MainActivity) : MethodChannel.MethodCallHandler {
    companion object {
        const val permissionCode = 7321
        const val source = "https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/42d538a932e8d5b12e6b3b455f5572560bd60b2c/gemma3-1b-it-int4.litertlm"
    }
    private val main = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private val locales = setOf("zh-TW","en-US","vi-VN","id-ID","th-TH","ko-KR","ja-JP")
    private var engine: Engine? = null
    @Volatile private var conversation: Conversation? = null
    private var generationId: String? = null
    private val cancelled = AtomicBoolean(false)
    private var voiceId: String? = null
    private var voiceReply: MethodChannel.Result? = null
    private var voiceLocale = "zh-TW"
    private var recognizer: SpeechRecognizer? = null
    private var transcript = ""
    private var finishingVoice = false
    private var timer: Runnable? = null
    private val model get() = File(activity.filesDir, "CodefestAI/gemma3-1b-it-int4.litertlm")
    private fun error(code: String) = mapOf("status" to "error", "code" to code)
    private fun receipt(): String? = try {
        val receipt = JSONObject(File(activity.filesDir, "CodefestAI/receipt.json").readText())
        receipt.getString("sha256").takeIf { receipt.getString("source") == source && it == "1325ae366d31950f137c9c357b9fa89448b176d76998180c08ceaca78bba98be" && model.length() == 584417280L }
    } catch (_: Exception) { null }
    private fun verify(expected: String): Boolean {
        val digest = MessageDigest.getInstance("SHA-256")
        model.inputStream().use { input ->
            val buffer = ByteArray(1024 * 1024)
            while (true) { val n = input.read(buffer); if (n < 0) break; digest.update(buffer, 0, n) }
        }
        return digest.digest().joinToString("") { "%02x".format(it) } == expected
    }
    // Android itself selects this on-device service. Refuse unknown OEM providers rather than falling back to cloud speech.
    private fun voiceAvailable(): Boolean = try {
        if (Build.VERSION.SDK_INT < 31 || !SpeechRecognizer.isOnDeviceRecognitionAvailable(activity)) false
        else {
            val resource = activity.resources.getIdentifier("config_defaultOnDeviceSpeechRecognitionService", "string", "android")
            val component = if (resource != 0) ComponentName.unflattenFromString(activity.getString(resource)) else null
            val packageName = component?.packageName
            if (packageName !in setOf("com.google.android.tts", "com.google.android.googlequicksearchbox")) false
            else {
                val flags = activity.packageManager.getApplicationInfo(packageName!!, 0).flags
                flags and (ApplicationInfo.FLAG_SYSTEM or ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0
            }
        }
    } catch (_: Exception) { false }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("requestId") ?: ""
        when (call.method) {
            "status" -> result.success(mapOf("status" to "success", "modelReady" to (receipt() != null), "voiceAvailable" to voiceAvailable(), "model" to "Gemma 3 1B INT4"))
            "generate" -> {
                val prompt = call.argument<String>("prompt")
                if (generationId != null || voiceId != null) { result.success(error("busy")); return }
                if (prompt.isNullOrBlank() || prompt.length > 6000) { result.success(error("invalid_input")); return }
                val hash = receipt()
                if (hash == null) { result.success(error("model_missing")); return }
                generationId = id; cancelled.set(false)
                executor.execute {
                    var response: Map<String, Any>
                    try {
                        if (engine == null) {
                            check(verify(hash))
                            check(!cancelled.get())
                            val loaded = Engine(EngineConfig(modelPath = model.absolutePath, backend = Backend.CPU(), maxNumTokens = 4096, cacheDir = activity.cacheDir.path))
                            try { loaded.initialize(); engine = loaded } catch (e: Exception) { loaded.close(); throw e }
                        }
                        check(!cancelled.get())
                        engine!!.createConversation(ConversationConfig(samplerConfig = SamplerConfig(topK = 40, topP = 0.9, temperature = 0.2))).use { chat ->
                            check(!cancelled.get())
                            conversation = chat
                            val reply = chat.sendMessage(prompt, repetitionPenaltyConfig = RepetitionPenaltyConfig(repetitionPenalty = 1.15f), noRepeatNgramConfig = NoRepeatNgramConfig(noRepeatNgramSize = 4), maxOutputToken = 256).toString()
                            response = if (cancelled.get()) error("cancelled") else mapOf("status" to "success", "text" to reply.take(6000))
                        }
                    } catch (_: Exception) { response = error(if (cancelled.get()) "cancelled" else "inference_failed") }
                    conversation = null
                    main.post { generationId = null; result.success(response) }
                }
            }
            "voice" -> {
                if (voiceId != null || generationId != null) { result.success(error("busy")); return }
                val locale = call.argument<String>("locale") ?: "zh-TW"
                if (locale !in locales || !voiceAvailable()) { result.success(error("voice_unavailable")); return }
                voiceId = id; voiceReply = result; voiceLocale = locale; transcript = ""; finishingVoice = false
                if (activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) startVoice()
                else activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), permissionCode)
            }
            "stopVoice" -> { stopVoiceCapture(); result.success(mapOf("status" to "success")) }
            "cancel" -> {
                val target = call.argument<String>("targetRequestId")
                if (target == generationId) cancelGeneration()
                if (target == voiceId) finishVoice(false)
                result.success(mapOf("status" to "success"))
            }
            "unload" -> { background(); result.success(mapOf("status" to "success")) }
            else -> result.notImplemented()
        }
    }
    fun permissionResult(granted: Boolean) {
        if (voiceId == null) return
        if (granted) startVoice() else finishVoice(false, "permission_denied")
    }
    private fun startVoice() {
        if (voiceId == null || Build.VERSION.SDK_INT < 31) return
        val id = voiceId
        try {
            if (!voiceAvailable()) { finishVoice(false, "voice_unavailable"); return }
            val speech = SpeechRecognizer.createOnDeviceSpeechRecognizer(activity)
            recognizer = speech
            speech.setRecognitionListener(object: RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) {}
                override fun onBeginningOfSpeech() {}
                override fun onRmsChanged(rmsdB: Float) {}
                override fun onBufferReceived(buffer: ByteArray?) {}
                override fun onEndOfSpeech() {}
                override fun onError(error: Int) { if (voiceId == id) finishVoice(false, if (error == SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS) "permission_denied" else "voice_unavailable") }
                override fun onResults(results: Bundle?) { if (voiceId == id) { transcript = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull().orEmpty().take(500); finishVoice(true) } }
                override fun onPartialResults(results: Bundle?) { if (voiceId == id) transcript = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull().orEmpty().take(500) }
                override fun onEvent(eventType: Int, params: Bundle?) {}
            })
            speech.startListening(Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM).putExtra(RecognizerIntent.EXTRA_LANGUAGE, voiceLocale).putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS,true).putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE,true))
            timer = Runnable { if (voiceId == id) stopVoiceCapture() }.also { main.postDelayed(it,30000) }
        } catch (_: Exception) { finishVoice(false, "voice_unavailable") }
    }
    private fun stopVoiceCapture() {
        if (voiceId == null || finishingVoice) return
        finishingVoice = true
        timer?.let { main.removeCallbacks(it) }
        try { recognizer?.stopListening() } catch (_: Exception) { finishVoice(false, "voice_unavailable"); return }
        timer = Runnable { finishVoice(transcript.isNotBlank(), "no_speech") }.also { main.postDelayed(it,3000) }
    }
    private fun finishVoice(success: Boolean, code: String = "cancelled") {
        val reply = voiceReply ?: return
        voiceReply = null; voiceId = null; finishingVoice = false
        timer?.let { main.removeCallbacks(it) }; timer = null
        recognizer?.cancel(); recognizer?.destroy(); recognizer = null
        reply.success(if (success && transcript.isNotBlank()) mapOf("status" to "success", "text" to transcript) else error(if (success) "no_speech" else code))
        transcript = ""
    }
    private fun cancelGeneration() { cancelled.set(true); try { conversation?.cancelProcess() } catch (_: Exception) {} }
    fun background() {
        cancelGeneration(); finishVoice(false)
        executor.execute { engine?.close(); engine = null }
    }
    fun destroy() { background(); executor.shutdown() }
}
