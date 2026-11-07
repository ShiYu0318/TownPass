// SPDX-License-Identifier: AGPL-3.0-or-later
import Flutter
import UIKit
import Speech
import AVFoundation
import CryptoKit
import LiteRTLM

final class CodefestAI: NSObject, FlutterPlugin {
  static let source = "https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/42d538a932e8d5b12e6b3b455f5572560bd60b2c/gemma3-1b-it-int4.litertlm"
  private var engine: Engine?
  private var conversation: Conversation?
  private var generation: Task<Void, Never>?
  private var generationId: String?
  private var voiceId: String?
  private var voiceResult: FlutterResult?
  private var audio: AVAudioEngine?
  private var speechRequest: SFSpeechAudioBufferRecognitionRequest?
  private var speechTask: SFSpeechRecognitionTask?
  private var voiceTimer: Timer?
  private var transcript = ""
  private var finishingVoice = false
  private var installedTap = false
  private let locales: Set<String> = ["zh-TW","en-US","vi-VN","id-ID","th-TH","ko-KR","ja-JP"]
  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = CodefestAI()
    let channel = FlutterMethodChannel(name: "codefest/on_device_ai", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: channel)
    NotificationCenter.default.addObserver(instance, selector: #selector(instance.background), name: UIApplication.didEnterBackgroundNotification, object: nil)
    NotificationCenter.default.addObserver(instance, selector: #selector(instance.background), name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
  }
  private var directory: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("CodefestAI") }
  private var model: URL { directory.appendingPathComponent("gemma3-1b-it-int4.litertlm") }
  private func receipt() -> String? {
    guard let data = try? Data(contentsOf: directory.appendingPathComponent("receipt.json")),
      let value = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      value["source"] as? String == Self.source,
      let digest = value["sha256"] as? String, digest.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
      let attributes = try? FileManager.default.attributesOfItem(atPath: model.path),
      (attributes[.size] as? NSNumber)?.int64Value == 584417280 else { return nil }
    return digest
  }
  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let id = args["requestId"] as? String ?? ""
    let locale = args["locale"] as? String ?? "zh-TW"
    switch call.method {
    case "status":
      let recognizer = locales.contains(locale) ? SFSpeechRecognizer(locale: Locale(identifier: locale)) : nil
      result(["status":"success", "modelReady":receipt() != nil, "voiceAvailable":recognizer?.supportsOnDeviceRecognition == true, "model":"Gemma 3 1B INT4"])
    case "generate":
      guard generationId == nil else { result(error("busy")); return }
      guard let prompt = args["prompt"] as? String, !prompt.isEmpty, prompt.utf16.count <= 6000 else { result(error("invalid_input")); return }
      guard let expected = receipt() else { result(error("model_missing")); return }
      generationId = id
      let path = model.path
      generation = Task { @MainActor [self] in
        do {
          if engine == nil {
            let valid = await Task.detached(priority: .userInitiated) { Self.verify(path, expected) }.value
            guard valid else { throw NSError(domain:"model_integrity", code:1) }
            try Task.checkCancellation()
            let config = try EngineConfig(modelPath: path, backend: .cpu(), maxNumTokens: 4096, cacheDir: NSTemporaryDirectory())
            let loaded = Engine(engineConfig: config)
            try await loaded.initialize()
            try Task.checkCancellation()
            engine = loaded
          }
          guard let current = engine else { throw NSError(domain:"model_missing",code:1) }
          let chat = try await current.createConversation()
          conversation = chat
          let reply = try await chat.sendMessage(Message(prompt), maxOutputTokens: 256)
          try Task.checkCancellation()
          result(["status":"success", "text":String(reply.toString.prefix(6000))])
        } catch {
          result(self.error(Task.isCancelled ? "cancelled" : "inference_failed"))
        }
        if generationId == id { generationId = nil; generation = nil; conversation = nil }
      }
    case "voice": startVoice(id, locale, result)
    case "stopVoice": stopVoiceCapture(); result(["status":"success"])
    case "cancel":
      let target = args["targetRequestId"] as? String
      if target == generationId { cancelGeneration() }
      if target == voiceId { finishVoice(success: false) }
      result(["status":"success"])
    case "unload": background(); result(["status":"success"])
    default: result(FlutterMethodNotImplemented)
    }
  }
  private static func verify(_ path: String, _ expected: String) -> Bool {
    guard let stream = InputStream(fileAtPath:path) else { return false }
    stream.open(); defer { stream.close() }
    var digest = SHA256(), buffer = [UInt8](repeating:0, count:1024*1024)
    while true {
      let count = stream.read(&buffer, maxLength:buffer.count)
      if count < 0 { return false }; if count == 0 { break }
      digest.update(data:Data(buffer.prefix(count)))
    }
    return digest.finalize().map { String(format:"%02x",$0) }.joined() == expected
  }
  private func error(_ code: String) -> [String:Any] { ["status":"error","code":code] }
  private func cancelGeneration() { generation?.cancel(); try? conversation?.cancel() }
  @objc private func background() { cancelGeneration(); finishVoice(success:false); engine = nil }
  private func startVoice(_ id: String, _ locale: String, _ result: @escaping FlutterResult) {
    guard voiceId == nil, generationId == nil else { result(error("busy")); return }
    guard locales.contains(locale), let recognizer = SFSpeechRecognizer(locale:Locale(identifier:locale)), recognizer.supportsOnDeviceRecognition else { result(error("voice_unavailable")); return }
    voiceId = id; voiceResult = result; transcript = ""; finishingVoice = false
    SFSpeechRecognizer.requestAuthorization { [weak self] status in
      DispatchQueue.main.async {
        guard let self, self.voiceId == id else { return }
        guard status == .authorized else { self.finishVoice(success:false, code:"permission_denied"); return }
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
          DispatchQueue.main.async {
            guard self.voiceId == id else { return }
            guard granted else { self.finishVoice(success:false, code:"permission_denied"); return }
            do {
              let session = AVAudioSession.sharedInstance()
              try session.setCategory(.record, mode:.measurement, options:[])
              try session.setActive(true)
              let request = SFSpeechAudioBufferRecognitionRequest()
              request.requiresOnDeviceRecognition = true
              request.shouldReportPartialResults = true
              let audio = AVAudioEngine()
              self.audio = audio; self.speechRequest = request
              let node = audio.inputNode, format = audio.inputNode.outputFormat(forBus:0)
              guard format.sampleRate > 0, format.channelCount > 0 else { throw NSError(domain:"no_microphone",code:1) }
              node.installTap(onBus:0, bufferSize:1024, format:format) { buffer, _ in request.append(buffer) }
              self.installedTap = true
              self.speechTask = recognizer.recognitionTask(with:request) { response, failure in
                DispatchQueue.main.async {
                  guard self.voiceId == id else { return }
                  if let response { self.transcript = String(response.bestTranscription.formattedString.prefix(500)) }
                  if response?.isFinal == true { self.finishVoice(success:true) }
                  else if failure != nil { self.finishVoice(success:!self.transcript.isEmpty, code:"voice_unavailable") }
                }
              }
              audio.prepare(); try audio.start()
              self.voiceTimer = Timer.scheduledTimer(withTimeInterval:30, repeats:false) { [weak self] _ in self?.stopVoiceCapture() }
            } catch { self.finishVoice(success:false, code:"voice_unavailable") }
          }
        }
      }
    }
  }
  private func stopVoiceCapture() {
    guard voiceId != nil, !finishingVoice else { return }
    finishingVoice = true
    audio?.stop()
    if installedTap { audio?.inputNode.removeTap(onBus:0); installedTap = false }
    speechRequest?.endAudio()
    voiceTimer?.invalidate()
    voiceTimer = Timer.scheduledTimer(withTimeInterval:3, repeats:false) { [weak self] _ in
      guard let self else { return }
      self.finishVoice(success:!self.transcript.isEmpty, code:"no_speech")
    }
  }
  private func finishVoice(success: Bool, code: String = "cancelled") {
    guard voiceId != nil else { return }
    let callback = voiceResult
    voiceId = nil; voiceResult = nil; finishingVoice = false
    voiceTimer?.invalidate(); voiceTimer = nil
    audio?.stop(); if installedTap { audio?.inputNode.removeTap(onBus:0); installedTap = false }; audio = nil
    speechRequest?.endAudio(); speechTask?.cancel(); speechTask = nil; speechRequest = nil
    try? AVAudioSession.sharedInstance().setActive(false, options:.notifyOthersOnDeactivation)
    callback?(success && !transcript.isEmpty ? ["status":"success","text":transcript] : error(success ? "no_speech" : code))
    transcript = ""
  }
}
