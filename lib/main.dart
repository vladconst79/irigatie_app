import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

part 'src/api_settings.dart';
part 'src/app.dart';
part 'src/screens.dart';
part 'src/dialogs.dart';
part 'src/widgets.dart';
part 'src/models.dart';
part 'src/irrigation_data_client.dart';
part 'src/helpers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final apiSettings = await ApiSettings.load();
  runApp(IrrigationApp(apiSettings: apiSettings));
}
