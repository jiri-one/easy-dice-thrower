import '../models/dice.dart';

DicePreset webEntryPreset(Uri uri) =>
    uri.host.toLowerCase() == 'zoldneri.jiri.one'
        ? DicePreset.mercenaries
        : DicePreset.classic;
