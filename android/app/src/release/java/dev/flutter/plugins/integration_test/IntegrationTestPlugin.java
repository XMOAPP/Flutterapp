package dev.flutter.plugins.integration_test;

import androidx.annotation.NonNull;
import io.flutter.embedding.engine.plugins.FlutterPlugin;

/**
 * Release-only compatibility stub for Flutter 3.41.x.
 *
 * The Flutter tool currently writes dev-only plugins into
 * GeneratedPluginRegistrant.java while the Gradle plugin correctly omits their
 * implementations from release builds. Keep this class empty so release builds
 * can register the generated entry without packaging integration_test.
 */
public final class IntegrationTestPlugin implements FlutterPlugin {
  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {}

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {}
}
