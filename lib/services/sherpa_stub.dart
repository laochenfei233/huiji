class OfflineRecognizer {
  OfflineRecognizer(dynamic config);
  dynamic createStream() => throw UnsupportedError('Web 不支持 sherpa-onnx');
  void decode(dynamic stream) {}
  dynamic getResult(dynamic stream) => throw UnsupportedError('Web 不支持 sherpa-onnx');
  void free() {}
}

class OfflineRecognizerConfig {
  OfflineRecognizerConfig({required dynamic model, String hotwordsFile = '', double hotwordsScore = 0});
}

class OfflineModelConfig {
  final dynamic senseVoice;
  final dynamic paraformer;
  final String tokens;
  final int numThreads;
  final bool debug;
  final String modelType;

  OfflineModelConfig({this.senseVoice, this.paraformer, required this.tokens, this.numThreads = 1, this.debug = false, this.modelType = ''});

  OfflineModelConfig.paraformer({required dynamic paraformer, required this.tokens, this.numThreads = 1, this.debug = false, this.modelType = ''})
      : senseVoice = null,
        this.paraformer = paraformer;
}

class OfflineSenseVoiceModelConfig {
  OfflineSenseVoiceModelConfig({required String model, required String language, required bool useInverseTextNormalization});
}

class OfflineParaformerModelConfig {
  OfflineParaformerModelConfig({required String model});
}

class VadModelConfig {
  VadModelConfig({required SileroVadModelConfig sileroVad, required int sampleRate, int numThreads = 1, bool debug = false});
}

class SileroVadModelConfig {
  SileroVadModelConfig({required String model, double threshold = 0.5, double minSilenceDuration = 0.5, double minSpeechDuration = 0.25, double maxSpeechDuration = 30.0, int windowSize = 512});
}

class VoiceActivityDetector {
  VoiceActivityDetector({required dynamic config, double bufferSizeInSeconds = 60});
  void acceptWaveform(dynamic samples) {}
  bool isDetected() => false;
  bool isEmpty() => true;
  dynamic front() => throw UnsupportedError('Web 不支持 sherpa-onnx');
  void pop() {}
  void flush() {}
  void free() {}
}

class CircularBuffer {
  CircularBuffer({required int capacity});
  int get size => 0;
  int get head => 0;
  void push(dynamic samples) {}
  dynamic get({required int startIndex, required int n}) => [];
  void pop(int n) {}
  void reset() {}
  void free() {}
}

void initBindings() {}
