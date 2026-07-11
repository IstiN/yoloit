import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Describes the PCM format used by the recorder and the WAV files it emits.
///
/// All capture sources (microphone via `record`, system loopback via the
/// ScreenCaptureKit channel added in Slice 3) are configured to deliver this
/// exact format so they can be summed sample-by-sample without resampling.
class PcmWavFormat {
  const PcmWavFormat({
    this.sampleRate = 48000,
    this.numChannels = 2,
    this.bitsPerSample = 16,
  });

  final int sampleRate;
  final int numChannels;
  final int bitsPerSample;

  int get byteRate => sampleRate * numChannels * bitsPerSample ~/ 8;
  int get blockAlign => numChannels * bitsPerSample ~/ 8;
}

/// Writes a RIFF/WAVE file with a 16-bit little-endian PCM payload.
///
/// The header is written up front with a zero data size and patched in
/// [close] once the total number of bytes is known, which keeps the payload
/// streaming-friendly (no need to buffer the whole recording in memory).
class PcmWavSink {
  PcmWavSink._(this._raf, this.format);

  final RandomAccessFile _raf;
  final PcmWavFormat format;
  int _dataSize = 0;

  /// Number of payload bytes written so far (excludes the 44-byte header).
  int get dataSize => _dataSize;

  /// Approximate duration of the audio written so far.
  Duration get duration {
    final rate = format.byteRate;
    if (rate <= 0) return Duration.zero;
    return Duration(microseconds: (_dataSize * 1000000) ~/ rate);
  }

  /// Creates (or truncates) [file] and writes a placeholder WAV header.
  static Future<PcmWavSink> create(
    File file, {
    PcmWavFormat format = const PcmWavFormat(),
  }) async {
    await file.parent.create(recursive: true);
    final raf = await file.open(mode: FileMode.write);
    final sink = PcmWavSink._(raf, format);
    await sink._writeHeader(0);
    return sink;
  }

  /// Appends a raw interleaved 16-bit little-endian PCM chunk.
  Future<void> add(Uint8List bytes) async {
    if (bytes.isEmpty) return;
    await _raf.setPosition(await _raf.length());
    await _raf.writeFrom(bytes);
    _dataSize += bytes.length;
  }

  /// Finalizes the RIFF/data sizes and closes the underlying file.
  Future<void> close() async {
    await _writeHeader(_dataSize);
    await _raf.close();
  }

  Future<void> _writeHeader(int dataSize) async {
    final header = ByteData(44);
    var offset = 0;

    void writeTag(String tag) {
      for (final codeUnit in tag.codeUnits) {
        header.setUint8(offset++, codeUnit);
      }
    }

    writeTag('RIFF');
    header.setUint32(offset, 36 + dataSize, Endian.little);
    offset += 4;
    writeTag('WAVE');
    writeTag('fmt ');
    header.setUint32(offset, 16, Endian.little); // fmt chunk size
    offset += 4;
    header.setUint16(offset, 1, Endian.little); // PCM
    offset += 2;
    header.setUint16(offset, format.numChannels, Endian.little);
    offset += 2;
    header.setUint32(offset, format.sampleRate, Endian.little);
    offset += 4;
    header.setUint32(offset, format.byteRate, Endian.little);
    offset += 4;
    header.setUint16(offset, format.blockAlign, Endian.little);
    offset += 2;
    header.setUint16(offset, format.bitsPerSample, Endian.little);
    offset += 2;
    writeTag('data');
    header.setUint32(offset, dataSize, Endian.little);
    offset += 4;

    await _raf.setPosition(0);
    await _raf.writeFrom(header.buffer.asUint8List());
  }
}

/// Encodes a single signed 16-bit sample as little-endian bytes (test helper).
Uint8List pcm16Sample(int sample) {
  final data = ByteData(2)..setInt16(0, sample, Endian.little);
  return data.buffer.asUint8List();
}

/// Concatenates [samples] into one interleaved 16-bit LE buffer (test helper).
Uint8List pcm16Samples(List<int> samples) {
  final data = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(i * 2, samples[i], Endian.little);
  }
  return data.buffer.asUint8List();
}

/// Reads the 16-bit LE sample at index [i] from [bytes] (test helper).
int readPcm16Sample(Uint8List bytes, int i) =>
    ByteData.sublistView(bytes).getInt16(i * 2, Endian.little);

/// Mixes two 16-bit little-endian PCM streams into one with hard clipping.
///
/// Samples are summed pairwise and saturated to the signed 16-bit range so
/// two loud sources never wrap around. If one stream is shorter, the missing
/// tail is treated as silence and the longer stream is copied through. The
/// returned length is always even and equals `max(a.length, b.length)` rounded
/// up to a whole sample.
Uint8List mixPcm16(Uint8List a, Uint8List b) {
  final aSamples = a.length ~/ 2;
  final bSamples = b.length ~/ 2;
  final total = math.max(aSamples, bSamples);

  final aView = ByteData.sublistView(a);
  final bView = ByteData.sublistView(b);
  final out = ByteData(total * 2);

  for (var i = 0; i < total; i++) {
    final sa = i < aSamples ? aView.getInt16(i * 2, Endian.little) : 0;
    final sb = i < bSamples ? bView.getInt16(i * 2, Endian.little) : 0;
    final sum = (sa + sb).clamp(-32768, 32767);
    out.setInt16(i * 2, sum, Endian.little);
  }
  return out.buffer.asUint8List();
}
