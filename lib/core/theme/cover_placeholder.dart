// lib/core/theme/cover_placeholder.dart
//
// Обложка для трека без своей — нейтральная, в цветах приложения. До 1.0.1 на
// этом месте стояла тестовая картинка (mock_cover.jpg), и у всех импортированных
// своих файлов оказывалась одна и та же чужая обложка.

import 'package:flutter/painting.dart';

const kCoverPlaceholder = AssetImage('assets/images/cover_placeholder.png');
