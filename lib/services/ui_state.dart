import 'package:flutter/material.dart';
import 'settings.dart';

class UiState {
  static final UiState instance = UiState._();
  UiState._();

  // Live notifiers for UI
  final ValueNotifier<Color> backgroundColor = ValueNotifier<Color>(const Color(0xFF0f172a));
  final ValueNotifier<Color> cardColor = ValueNotifier<Color>(const Color(0xFF111827));
  final ValueNotifier<bool> haptics = ValueNotifier<bool>(true);

  Future<void> load() async {
    final theme = await SettingsService.getThemeColors();
    backgroundColor.value = theme.$1;
    cardColor.value = theme.$2;
    haptics.value = await SettingsService.getHapticsEnabled();
  }

  // Removed global compact density toggle; cards use consistent spacing

  Future<void> setTheme({required Color background, required Color card}) async {
    backgroundColor.value = background;
    cardColor.value = card;
    await SettingsService.setThemeColors(background: background, card: card);
  }

  Future<void> setHaptics(bool v) async {
    haptics.value = v;
    await SettingsService.setHapticsEnabled(v);
  }
}
