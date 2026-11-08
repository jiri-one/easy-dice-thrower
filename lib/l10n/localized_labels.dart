import 'package:flutter/widgets.dart';

import '../models/dice.dart';
import '../tray_controller.dart';
import 'generated/app_localizations.dart';

extension LocalizedContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

extension LocalizedLabels on AppLocalizations {
  String dieName(DieDefinition definition) =>
      definition.customName ??
      switch (definition.kind) {
        DieKind.numeric => 'd${definition.sides}',
        DieKind.mercenary => mercenaryDieName,
        DieKind.text => customDieName(definition.sides),
      };

  String faceLabel(DieFace face) => switch (face.kind) {
    FaceKind.numeric || FaceKind.text => face.label,
    FaceKind.blank => blankFace,
    FaceKind.oneSword => oneSword,
    FaceKind.twoSwords => twoSwords,
  };

  String presetName(DicePreset preset) => switch (preset) {
    DicePreset.mercenaries => presetMercenaries,
    DicePreset.classic => presetClassic,
    DicePreset.rpg => presetRpg,
    DicePreset.empty => presetEmpty,
  };

  String setTitle(DiceSet set) =>
      set.preset == null ? set.name : presetName(set.preset!);

  String trayTitle(TrayController tray) =>
      tray.preset == null
          ? tray.setName ?? customTray
          : presetName(tray.preset!);

  String trayMessage(TrayMessage message) => switch (message) {
    TrayMessage.loadFailed => loadFailed,
    TrayMessage.saveFailed => saveFailed,
    TrayMessage.rollFailed => rollFailed,
    TrayMessage.trayFull => trayFull,
    TrayMessage.invalidSetName => invalidSetName,
  };
}
