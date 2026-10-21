import '../lib/backend/models/message_order.dart';
void main() {
 final rows = [
 {'id':'3','body':'bay','created_at':'2026-10-21T10:03:00Z'},
 {'id':'1','body':'hi','created_at':'2026-10-21T10:01:00Z'},
 {'id':'2','body':'hello','created_at':'2026-10-21T10:02:00Z'}];
 final sorted = chronologicalMessages(rows);
 if(sorted.map((r)=>r['body']).join(',')!='hi,hello,bay') throw StateError('Wrong order');
 if(rows.first['body']!='bay') throw StateError('Input mutated');
 final ties = chronologicalMessages([{'id':'b','created_at':'2026-10-21T10:01:00Z'},{'id':'a','created_at':'2026-10-21T13:01:00+03:00'}]);
 if(ties.first['id']!='a') throw StateError('Unstable tie order');
 print('PASS chronological order, immutable input, stable equal timestamps');
}
