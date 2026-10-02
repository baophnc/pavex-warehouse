import 'package:flutter_test/flutter_test.dart';
import 'package:pavex_warehouse/data/models.dart';

void main() {
  test('an inbox page reads notices, the next cursor and the unread count', () {
    final page = NotificationPage.fromJson({
      'items': [
        {
          'id': 'a',
          'code': 'message.hub',
          'category': 'Operations',
          'severity': 'Info',
          'title': 'Họp đầu ca 7h30',
          'body': 'Các bạn có mặt lúc 7h30.',
          'isRead': false,
          'createdAt': '2026-10-02T08:00:00Z',
          'senderUserId': 'manager',
        },
      ],
      'nextCursor': null,
      'unreadCount': 1,
    });

    expect(page.unreadCount, 1);
    expect(page.nextCursor, isNull);
    expect(page.items.single.isMessage, isTrue);
    expect(page.items.single.read().isRead, isTrue);
  });

  test('hub staff may write to couriers and drivers', () {
    final options = MessageOptions.fromJson({
      'hubIds': ['hub'],
      'allHubs': false,
      'audiences': ['HUB_COURIERS', 'HUB_DRIVERS'],
      'canMessageShops': true,
    });

    expect(options.audiences.map((value) => MessageOptions.audienceLabels[value]), ['Bưu tá', 'Tài xế trung chuyển']);
  });
}
