import 'dart:typed_data';

const chatMediaLimit = 10 * 1024 * 1024;
const voiceSecondsLimit = 60;

/// Body stored for a media message sent without a caption (and for every
/// media message sent before captions existed).
const chatMediaDefaultBodies = {'Photo', 'Video', 'Voice message'};

String chatMediaDefaultBody(String kind) => kind == 'image'
    ? 'Photo'
    : kind == 'video'
    ? 'Video'
    : 'Voice message';

/// The caption of a media message, or null when it has none.
String? chatMediaCaption(Object? body) {
  final text = body?.toString().trim() ?? '';
  return text.isEmpty || chatMediaDefaultBodies.contains(text) ? null : text;
}

String imageMime(Uint8List bytes) {
  if (bytes.length < 12 || bytes.length > chatMediaLimit) {
    throw ArgumentError('Choose a PNG, JPEG or WebP image up to 10 MB.');
  }
  if (bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff)
    return 'image/jpeg';
  if (bytes.take(8).join(',') == '137,80,78,71,13,10,26,10') return 'image/png';
  if (String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
      String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP')
    return 'image/webp';
  throw ArgumentError('Choose a PNG, JPEG or WebP image.');
}

// Mono signed PCM16 at 16000 Hz -> a portable WAV; no local recording files.
Uint8List voiceWav(Uint8List pcm) {
  if (pcm.length < 16000 ||
      pcm.length > 16000 * 2 * voiceSecondsLimit ||
      pcm.length.isOdd) {
    throw ArgumentError('Record between 0.5 and 60 seconds.');
  }
  final result = Uint8List(44 + pcm.length);
  final header = ByteData.sublistView(result);
  void textAt(int offset, String text) =>
      result.setRange(offset, offset + text.length, text.codeUnits);
  textAt(0, 'RIFF');
  header.setUint32(4, 36 + pcm.length, Endian.little);
  textAt(8, 'WAVE');
  textAt(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, 1, Endian.little);
  header.setUint32(24, 16000, Endian.little);
  header.setUint32(28, 32000, Endian.little);
  header.setUint16(32, 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  textAt(36, 'data');
  header.setUint32(40, pcm.length, Endian.little);
  result.setRange(44, result.length, pcm);
  return result;
}

String videoMime(Uint8List bytes) {
  if (bytes.length < 16 ||
      bytes.length > chatMediaLimit ||
      String.fromCharCodes(bytes.sublist(4, 8)) != 'ftyp') {
    throw ArgumentError('Choose an MP4 video up to 10 MB.');
  }
  final brand = String.fromCharCodes(bytes.sublist(8, 12));
  if (!{
    'isom',
    'iso2',
    'iso4',
    'iso5',
    'iso6',
    'mp41',
    'mp42',
    'avc1',
    'M4V ',
    'dash',
  }.contains(brand)) {
    throw ArgumentError('Choose an MP4 video.');
  }
  return 'video/mp4';
}
