import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qingya/app.dart';
import 'package:qingya/data/prefs/settings_store.dart';
import 'package:qingya/ui/widgets/assets.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<Finder> pumpApp(
    WidgetTester tester, {
    required Map<String, Object> preferences,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues(preferences);
    final sharedPreferences = await SharedPreferences.getInstance();
    final cacheKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(key: cacheKey),
      ),
    );
    const assets = [
      QingyaAssets.catHeroWinkV3,
      QingyaAssets.catBrandAvatarV3,
      QingyaAssets.catEmptySleepV3,
      QingyaAssets.catDetailPeekV3,
      QingyaAssets.catWhiteBustV3,
      QingyaAssets.catGrayTabbyBustV3,
      QingyaAssets.catOrangeTabbyBustV3,
      QingyaAssets.catRagdollBustV3,
      QingyaAssets.deviceLaptop,
      QingyaAssets.deviceDesktop,
      QingyaAssets.deviceServer,
    ];
    await tester.runAsync(() async {
      for (final asset in assets) {
        await precacheImage(AssetImage(asset), cacheKey.currentContext!);
      }
    });
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: ProviderScope(
          overrides: [
            sharedPrefsProvider.overrideWithValue(sharedPreferences),
          ],
          child: const QingyaApp(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 800));
    return find.byKey(boundaryKey);
  }

  testWidgets('prototype main screens', (tester) async {
    final boundary = await pumpApp(
      tester,
      preferences: const {'demo_mode': true},
    );

    await tester.tap(find.text('设备'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('首页'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(boundary, matchesGoldenFile('goldens/home.png'));

    await tester.tap(find.text('设备'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(boundary, matchesGoldenFile('goldens/devices.png'));

    await tester.tap(find.text('ThinkPad-X1'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(boundary, matchesGoldenFile('goldens/device_detail.png'));

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(boundary, matchesGoldenFile('goldens/settings.png'));
  });

  testWidgets('prototype first-run screen', (tester) async {
    final boundary = await pumpApp(tester, preferences: const {});
    await expectLater(boundary, matchesGoldenFile('goldens/welcome.png'));
  });
}
