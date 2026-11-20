import 'dart:typed_data';
import '../lib/backend/chat/chat_media_policy.dart';
void main() {
 var checks=0;
 void check(bool ok) {if (!ok) throw StateError('check ${checks+1} failed'); checks++;}
 void rejects(void Function() run) {try {run();} on ArgumentError {checks++;return;} throw StateError('expected rejection');}
 check(imageMime(Uint8List.fromList([137,80,78,71,13,10,26,10,0,0,0,0]))=='image/png');
 check(imageMime(Uint8List.fromList([255,216,255,0,0,0,0,0,0,0,0,0]))=='image/jpeg');
 check(imageMime(Uint8List.fromList('RIFF0000WEBP'.codeUnits))=='image/webp');
 rejects(() => imageMime(Uint8List.fromList('<svg>unsafe</svg>'.codeUnits)));
 rejects(() => imageMime(Uint8List(chatMediaLimit+1)));
 rejects(() => voiceWav(Uint8List(15998)));
 rejects(() => voiceWav(Uint8List(16001)));
 rejects(() => voiceWav(Uint8List(1920002)));
 final wav=voiceWav(Uint8List(32000));final h=ByteData.sublistView(wav);
 check(wav.length==32044); check(String.fromCharCodes(wav.sublist(0,4))=='RIFF');
 check(h.getUint32(24,Endian.little)==16000);check(h.getUint16(22,Endian.little)==1);
 check(h.getUint16(34,Endian.little)==16);check(h.getUint32(40,Endian.little)==32000);
 check(voiceWav(Uint8List(1920000)).length==1920044);
 print('$checks media validation/WAV checks passed');
}
