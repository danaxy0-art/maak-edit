import 'dart:typed_data';
import '../lib/backend/chat/chat_media_policy.dart';
void main() {
 var checks=0;
 final valid=Uint8List.fromList([0,0,0,16,...'ftypisom'.codeUnits,0,0,0,0]);
 if(videoMime(valid)!='video/mp4') throw StateError('MP4 rejected'); checks++;
 for (final invalid in [Uint8List(4),Uint8List(chatMediaLimit+1),Uint8List.fromList([0,0,0,16,...'ftypavif'.codeUnits,0,0,0,0]),Uint8List.fromList('<svg>not video</svg>'.codeUnits)]) {
  try {videoMime(invalid);throw StateError('Invalid video accepted');} on ArgumentError {checks++;}
 }
 print('$checks MP4 signature/size validation checks passed');
}
