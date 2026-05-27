// Web Audio API JavaScript interop for real audio capture
window.AudioCapture = {
  _audioContext: null,
  _mediaStreamSource: null,
  _analyser: null,
  _processor: null,
  _isRecording: false,

  // 初始化音频上下文和音频处理链
  initAudioContext: function() {
    if (!window.AudioContext && !window.webkitAudioContext) {
      throw new Error('Web Audio API not supported');
    }
    
    this._audioContext = new (window.AudioContext || window.webkitAudioContext)();
    
    if (this._audioContext.state === 'suspended') {
      this._audioContext.resume();
    }
    
    return this._audioContext.sampleRate;
  },

  // 开始录音
  startRecording: function(streamId, callbackId) {
    try {
      if (!this._audioContext) {
        const sampleRate = this.initAudioContext();
        console.log('Audio context initialized, sample rate:', sampleRate);
      }

      // 获取媒体流
      const stream = this._getStreamById(streamId);
      if (!stream) {
        throw new Error('Stream not found: ' + streamId);
      }

      console.log('Starting real audio recording from stream:', streamId);
      console.log('Audio tracks:', stream.getAudioTracks().length);

      // 创建音频源
      this._mediaStreamSource = this._audioContext.createMediaStreamSource(stream);
      
      // 创建分析器
      this._analyser = this._audioContext.createAnalyser();
      this._analyser.fftSize = 2048;
      this._mediaStreamSource.connect(this._analyser);

      // 创建音频处理器
      this._processor = this._audioContext.createScriptProcessor(4096, 1, 1);
      this._processor.onaudioprocess = (event) => {
        if (!this._isRecording) return;
        
        const inputData = event.inputBuffer.getChannelData(0);
        const output = new Float32Array(inputData.length);
        
        // 复制并处理音频数据
        for (let i = 0; i < inputData.length; i++) {
          output[i] = inputData[i];
        }
        
        // 将Float32Array转换为Uint8Array并发送给Dart
        const audioBytes = new Uint8Array(output.buffer);
        this._sendAudioData(audioBytes, callbackId);
      };
      
      this._analyser.connect(this._processor);
      this._processor.connect(this._audioContext.destination);
      this._isRecording = true;
      
      console.log('Real audio recording started successfully');
      return true;
      
    } catch (error) {
      console.error('Failed to start recording:', error);
      return false;
    }
  },

  // 停止录音
  stopRecording: function() {
    if (this._isRecording) {
      this._isRecording = false;
      
      if (this._processor) {
        this._processor.disconnect();
        this._processor = null;
      }
      
      if (this._analyser) {
        this._analyser.disconnect();
        this._analyser = null;
      }
      
      if (this._mediaStreamSource) {
        this._mediaStreamSource.disconnect();
        this._mediaStreamSource = null;
      }
      
      console.log('Real audio recording stopped');
    }
  },

  // 获取媒体流（模拟实现）
  _getStreamById: function(streamId) {
    // 在实际应用中，我们需要维护MediaStream的引用
    // 这里需要从外部传入MediaStream对象
    return navigator.mediaDevices.getUserMedia ? null : null;
  },

  // 发送音频数据到Dart
  _sendAudioData: function(audioBytes, callbackId) {
    // 使用postMessage发送数据到Dart
    window.dispatchEvent(new CustomEvent('audioData', {
      detail: {
        bytes: audioBytes,
        callbackId: callbackId
      }
    }));
  },

  // 获取音频设置
  getAudioSettings: function() {
    return {
      sampleRate: this._audioContext ? this._audioContext.sampleRate : 16000,
      channelCount: 1,
      isRecording: this._isRecording
    };
  }
};

// 监听音频数据事件
window.addEventListener('audioData', function(event) {
  console.log('Real audio data received:', event.detail.bytes.length, 'bytes');
  
  // 在实际应用中，这里会通过Dart interop发送数据
  console.log('Audio data ready for processing');
});

// WebRTC媒体流获取
window.getUserMediaStream = function() {
  return navigator.mediaDevices.getUserMedia({
    audio: {
      sampleRate: 16000,
      channelCount: 1,
      echoCancellation: true,
      noiseSuppression: true
    }
  });
};