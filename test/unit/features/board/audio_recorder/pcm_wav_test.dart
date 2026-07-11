import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/audio_recorder/pcm_wav.dart';

String _tag(Uint8List bytes, int offset, int length) =>
    String.fromCharCodes(bytes.sublist(offset, offset + length));

int _u32(Uint8List bytes, int offset) =>
    ByteData.sublistView(bytes).getUint32(offset, Endian.little);

int _u16(Uint8List bytes, int offset) =>
    ByteData.sublistView(bytes).getUint16(offset, Endian.little);

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pcm_wav_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('PcmWavSink', () {
    test('writes a valid 48 kHz / stereo / 16-bit WAV header and payload',
        () async {
      final file = File('${tempDir.path}/out.wav');
      final payload = pcm16Samples(<int>[0, 1000, -1000, 16383]);

      final sink = await PcmWavSink.create(file);
      await sink.add(payload);
      expect(sink.dataSize, payload.length);
      await sink.close();

      final bytes = await file.readAsBytes();
      expect(bytes.length, 44 + payload.length);
      expect(_tag(bytes, 0, 4), 'RIFF');
      expect(_u32(bytes, 4), 36 + payload.length);
      expect(_tag(bytes, 8, 4), 'WAVE');
      expect(_tag(bytes, 12, 4), 'fmt ');
      expect(_u32(bytes, 16), 16);
      expect(_u16(bytes, 20), 1); // PCM
      expect(_u16(bytes, 22), 2); // channels
      expect(_u32(bytes, 24), 48000); // sample rate
      expect(_u32(bytes, 28), 192000); // byte rate
      expect(_u16(bytes, 32), 4); // block align
      expect(_u16(bytes, 34), 16); // bits per sample
      expect(_tag(bytes, 36, 4), 'data');
      expect(_u32(bytes, 40), payload.length);

      // Payload is copied verbatim starting at byte 44.
      expect(bytes.sublist(44), payload);
    });

    test('reports duration from byte rate', () async {
      final file = File('${tempDir.path}/dur.wav');
      final sink = await PcmWavSink.create(file);
      // One second of stereo 16-bit audio at 48 kHz = 192000 bytes.
      await sink.add(Uint8List(192000));
      expect(sink.duration.inMilliseconds, closeTo(1000, 1));
      await sink.close();
    });
  });

  group('mixPcm16', () {
    test('sums equal-length streams sample by sample', () {
      final a = pcm16Samples(<int>[1000, -2000, 0]);
      final b = pcm16Samples(<int>[500, 1000, -7]);
      final mixed = mixPcm16(a, b);

      expect(readPcm16Sample(mixed, 0), 1500);
      expect(readPcm16Sample(mixed, 1), -1000);
      expect(readPcm16Sample(mixed, 2), -7);
    });

    test('clips positive and negative overflow to the 16-bit range', () {
      final a = pcm16Samples(<int>[30000, -30000]);
      final b = pcm16Samples(<int>[30000, -30000]);
      final mixed = mixPcm16(a, b);

      expect(readPcm16Sample(mixed, 0), 32767);
      expect(readPcm16Sample(mixed, 1), -32768);
    });

    test('treats the shorter stream as silence', () {
      final a = pcm16Samples(<int>[100, 200, 300, 400]);
      final b = pcm16Samples(<int>[10, 20]);
      final mixed = mixPcm16(a, b);

      expect(mixed.length, a.length);
      expect(readPcm16Sample(mixed, 0), 110);
      expect(readPcm16Sample(mixed, 1), 220);
      expect(readPcm16Sample(mixed, 2), 300);
      expect(readPcm16Sample(mixed, 3), 400);
    });
  });
}
