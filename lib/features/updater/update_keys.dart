// lib/features/updater/update_keys.dart
//
// Публичные ключи, которыми подписан манифест обновлений (Ed25519, base64).
// Ключ карты — kid, он совпадает с полем kid в protogenix-update.json.
//
// Пара ключей создаётся командой
//   dart run tool/update_signing.dart keygen <kid> <путь-вне-репозитория>
// Приватная часть остаётся только у Orion, сюда вписывается публичная.
//
// Если карта пуста, приложение не принимает ни одного манифеста —
// проверка обновлений выключена.
//
// Смена ключа: добавить новый kid рядом со старым, выпустить версию,
// подписанную старым ключом, и только потом подписывать новым.

import 'dart:convert';

const Map<String, String> kUpdateSigningKeys = {
  // Создан Orion 2026-09-11; приватная часть — вне репозитория.
  'z43-2026': 'bCbR499zXx2FbObzz+fX/EwKJbKA08g9IMl76KG+FpA=',
};

Map<String, List<int>> decodeUpdateSigningKeys([
  Map<String, String> keys = kUpdateSigningKeys,
]) =>
    {for (final entry in keys.entries) entry.key: base64Decode(entry.value)};
