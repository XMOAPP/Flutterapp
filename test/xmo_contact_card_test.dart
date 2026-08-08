import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xmo/models/xmo_contact_card.dart';

void main() {
  test('creates Matrix metadata and a compatible vCard', () {
    final contact = XmoContactCard.create(
      displayName: 'Ada Lovelace',
      phoneNumber: '+44 20 1234 5678',
    );

    expect(contact.fileName, 'Ada_Lovelace.vcf');
    expect(contact.toJson(), {
      'version': 1,
      'display_name': 'Ada Lovelace',
      'phone_number': '+44 20 1234 5678',
    });

    final vCard = utf8.decode(contact.toVCardBytes());
    expect(vCard, contains('BEGIN:VCARD\r\nVERSION:3.0'));
    expect(vCard, contains('FN:Ada Lovelace'));
    expect(vCard, contains('TEL;TYPE=CELL:+44 20 1234 5678'));
    expect(vCard, endsWith('END:VCARD\r\n'));
  });

  test('sanitizes line breaks before creating metadata or vCard content', () {
    final contact = XmoContactCard.create(
      displayName: 'Ada\r\nInjected',
      phoneNumber: '+1 555\n123',
    );

    expect(contact.displayName, 'Ada  Injected');
    expect(contact.phoneNumber, '+1 555 123');
    expect(utf8.decode(contact.toVCardBytes()), isNot(contains('Injected\n')));
  });

  test('round trips XMO username, user ID, and avatar metadata', () {
    final contact = XmoContactCard.createXmoUser(
      displayName: 'Ada Lovelace',
      userId: '@ada:example.org',
      avatarUrl: 'mxc://example.org/avatar',
    );

    expect(contact.subtitle, '@ada');
    expect(contact.isXmoUser, isTrue);
    expect(contact.toJson()['avatar_url'], 'mxc://example.org/avatar');

    final restored = XmoContactCard.fromEventContent({
      xmoContactContentKey: contact.toJson(),
    });
    expect(restored?.userId, '@ada:example.org');
    expect(restored?.username, '@ada');
    expect(restored?.avatarUrl, 'mxc://example.org/avatar');
  });

  test('renders legacy Matrix ID display names as a friendly label', () {
    final contact = XmoContactCard.createXmoUser(
      displayName: '@hunter:example.org',
      userId: '@hunter:example.org',
    );

    expect(contact.displayLabel, 'Hunter');
    expect(contact.subtitle, '@hunter');
  });

  test('rejects malformed or unsupported event metadata', () {
    expect(
      XmoContactCard.fromEventContent({
        xmoContactContentKey: {
          'version': 2,
          'display_name': 'Ada',
          'phone_number': '+1',
        },
      }),
      isNull,
    );
    expect(
      XmoContactCard.fromEventContent({
        xmoContactContentKey: {
          'version': 1,
          'display_name': '',
          'phone_number': '+1',
        },
      }),
      isNull,
    );
  });
}
