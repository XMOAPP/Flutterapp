import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('invite deployment contract', () {
    test('Android registers the canonical verified App Link', () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();

      expect(manifest, contains('android:autoVerify="true"'));
      expect(manifest, contains('android:host="xmo.dpdns.org"'));
      expect(manifest, contains('android:pathPrefix="/join/"'));
      expect(manifest, contains('android:pathPrefix="/auth/callback"'));
      expect(manifest, contains('android:scheme="xmo" android:host="account"'));
      expect(
        manifest,
        isNot(contains('android:scheme="xmo" android:host="auth"')),
      );
    });

    test('Android retains warm-start links until Flutter is listening', () {
      final activity = File(
        'android/app/src/main/kotlin/com/xmo/xmo/MainActivity.kt',
      ).readAsStringSync();

      expect(activity, contains('if (linksReceiver == null)'));
      expect(activity, contains('initialLink = intent.dataString'));
      expect(activity, contains('linksReceiver?.onReceive'));
    });

    test('Netlify serves join routes with private preview headers', () {
      final redirects = File(
        'deploy/netlify-invite/_redirects',
      ).readAsStringSync();
      final headers = File('deploy/netlify-invite/_headers').readAsStringSync();

      expect(redirects, contains('/join/*  /join/index.html  200'));
      expect(headers, contains('Cache-Control: no-store'));
      expect(headers, contains('Referrer-Policy: no-referrer'));
      expect(headers, contains('X-Robots-Tag: noindex'));
      expect(headers, contains("default-src 'none'"));
      expect(headers, contains('frame-ancestors \'none\''));
    });

    test('browser fallback uses XMO endpoints and direct APK download', () {
      final page = File(
        'deploy/netlify-invite/join/index.html',
      ).readAsStringSync();

      expect(
        page,
        contains('https://xmo-matrix.centralindia.cloudapp.azure.com/auth/otp'),
      );
      expect(
        page,
        contains(
          'https://xmoappreleases2026.blob.core.windows.net/'
          'app-releases/xmo-latest.apk',
        ),
      );
      expect(page, contains('xmo://join/'));
      expect(page, contains('/avatar`'));
      expect(page, contains('data.avatarUrl'));
      expect(page, isNot(contains('matrix.to')));
    });

    test('asset links template targets the production package', () {
      final assetLinks = File(
        'deploy/netlify-invite/.well-known/assetlinks.json.template',
      ).readAsStringSync();

      expect(assetLinks, contains('com.xmo.xmo'));
      expect(
        assetLinks,
        contains('REPLACE_WITH_GOOGLE_PLAY_APP_SIGNING_SHA256'),
      );
    });

    test('deployment script validates and replaces the Play fingerprint', () {
      final script = File(
        'tools/prepare_netlify_invite.ps1',
      ).readAsStringSync();

      expect(script, contains('PlaySigningSha256'));
      expect(script, contains('Google Play App Signing'));
      expect(script, contains('REPLACE_WITH_GOOGLE_PLAY_APP_SIGNING_SHA256'));
      expect(script, contains("'assetlinks.json'"));
      expect(script, contains("'build\\netlify-invite'"));
      expect(script, contains("'com.xmo.xmo'"));
      expect(script, contains("'auth\\callback\\index.html'"));
    });

    test('SSO browser fallback does not execute or forward login tokens', () {
      final page = File(
        'deploy/netlify-invite/auth/callback/index.html',
      ).readAsStringSync();

      expect(page, contains('Return to XMO'));
      expect(page, isNot(contains('<script')));
      expect(page, isNot(contains('loginToken')));
    });

    test('private invite previews do not expose room topics', () {
      final handler = File(
        'auth_server/lib/src/handlers/invite_handler.dart',
      ).readAsStringSync();

      expect(
        handler,
        contains("if (joinMode == 'join' && topic != null) 'topic': topic"),
      );
    });
  });
}
