import 'package:ambulance_way/core/json_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('JsonReader', () {
    test('đọc được tên trường viết kiểu PascalCase lẫn camelCase', () {
      final pascal = JsonReader({'CaseId': 7, 'DriverName': 'An'});
      final camel = JsonReader({'caseId': 7, 'driverName': 'An'});

      for (final reader in [pascal, camel]) {
        expect(reader.integer('caseId'), 7);
        expect(reader.string('DRIVERNAME'), 'An');
      }
    });

    test('số nguyên, số thực và chuỗi số đều chuyển được', () {
      final reader = JsonReader({'a': 3, 'b': 3.0, 'c': '4', 'd': '10.5', 'e': 'x'});

      expect(reader.integer('a'), 3);
      expect(reader.integer('b'), 3);
      expect(reader.integer('c'), 4);
      expect(reader.number('a'), 3.0);
      expect(reader.number('d'), 10.5);
      expect(reader.intOrNull('e'), isNull);
      expect(reader.integer('missing', 9), 9);
    });

    test('chuỗi rỗng hoặc toàn khoảng trắng coi như không có', () {
      final reader = JsonReader({'a': '', 'b': '   ', 'c': ' x '});

      expect(reader.stringOrNull('a'), isNull);
      expect(reader.stringOrNull('b'), isNull);
      expect(reader.string('c'), 'x');
      expect(reader.string('a', 'mặc định'), 'mặc định');
    });

    test('object và mảng lồng nhau', () {
      final reader = JsonReader({
        'Driver': {'Name': 'An'},
        'Data': [
          {'Id': 1},
          'bỏ qua',
          {'Id': 2},
        ],
      });

      expect(reader.object('driver')?.string('name'), 'An');
      expect(reader.objects('data').map((item) => item.integer('id')), [1, 2]);
      expect(reader.object('missing'), isNull);
      expect(reader.objects('missing'), isEmpty);
    });

    test('tryFrom và listFrom chịu được dữ liệu sai kiểu', () {
      expect(JsonReader.tryFrom('text'), isNull);
      expect(JsonReader.tryFrom(null), isNull);
      expect(JsonReader.listFrom({'a': 1}), isEmpty);
    });
  });

  group('parseServerTime', () {
    test('thời điểm thiếu múi giờ được hiểu là UTC', () {
      final parsed = parseServerTime('2026-10-12T12:59:12.5070109');

      expect(parsed, isNotNull);
      expect(parsed!.isUtc, isFalse);
      expect(parsed.toUtc(), DateTime.utc(2026, 10, 12, 12, 59, 12, 507, 10));
    });

    test('thời điểm có Z hoặc offset giữ đúng thời khắc', () {
      expect(parseServerTime('2026-10-12T12:00:00Z')!.toUtc(), DateTime.utc(2026, 10, 12, 12));
      expect(parseServerTime('2026-10-12T19:00:00+07:00')!.toUtc(), DateTime.utc(2026, 10, 12, 12));
    });

    test('chuỗi hỏng trả về null', () {
      expect(parseServerTime(null), isNull);
      expect(parseServerTime(''), isNull);
      expect(parseServerTime('hôm qua'), isNull);
    });
  });
}
