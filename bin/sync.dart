// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:yaml/yaml.dart';

class OutputFormat {
  static const keyValueJson = 'key_value_json';
  static const androidStrings = 'android_strings';
  static const appleStrings = 'apple_strings';
}

List<String> supportedLocales = [];
late String fallbackLanguage;
late String translationsDir;
late String output;

const poEditorExportEndpoint = 'https://api.poeditor.com/v2/projects/export';
late String poEditorApiKey;
late String poEditorApiProjectId;

bool flutterEnabled = true;

bool nativeAndroidEnabled = false;
const nativeAndroidTransRoot = 'android/app/src/main/res/raw/';

bool nativeIosEnabled = false;
const nativeIosTransRoot = 'ios/Runner/';

void main(List<String> args) async {
  print('Export translations from PO Editor is started');

  try {
    await readConfig();

    for (final language in supportedLocales) {
      print('Export translations for language: $language');

      // Download the language in json format and update Flutter translations.
      String? url = await getLocaleFileUrl(language, OutputFormat.keyValueJson);
      if (url?.isNotEmpty == true) {
        print('Prepare to export Flutter translations from $url');
        String name = '$language.json';
        String translation = await getLocalizationTranslation(url!);
        if (translation.isNotEmpty) {

          if (flutterEnabled) {
            saveTranslationFile('$translationsDir$name', translation);
            print('Translations in $translationsDir$name have been updated.');
          }

          if (nativeAndroidEnabled) {
            print('Copy Flutter translations to Android project');
            saveTranslationFile('$nativeAndroidTransRoot$name', translation);
            print('Translations in $nativeAndroidTransRoot$name have been updated.');
          }

        } else {
          print('Got empty translations for $language, skipped.');
          continue;
        }
      }

      // Download the language in xml format and update Android translations.
      if (nativeIosEnabled) {
        url = await getLocaleFileUrl(language, OutputFormat.appleStrings);
        if (url?.isNotEmpty == true) {
          print('Prepare to export iOS translations from $url');
          String translation = await getLocalizationTranslation(url!);
          if (translation.isNotEmpty) {
            final langSuffix = language == 'pt' ? 'pt-PT' : language;
            final languageDirPath = '$nativeIosTransRoot$langSuffix.lproj';
            final languageDir = Directory(languageDirPath);
            if (!(await languageDir.exists())) await languageDir.create();
            final languageFile = '$languageDirPath/Localizable.strings';
            saveTranslationFile(languageFile, translation);
            print('Translations in $languageFile have been updated.');
          }
        }
      }
    }

    if (flutterEnabled) {
      print('Building keys...');
      final result = await Process.run('flutter', [
        'pub',
        'run',
        'easy_localization:generate',
        '--source-dir', translationsDir,
        '--source-file', '$fallbackLanguage.json',
        '-f', 'keys',
        '-o', output
      ], runInShell: true);

      if (result.exitCode == 0) {
        print(result.stdout);
      } else {
        print(result.stderr);
      }
    }

  } on Exception catch(e) {
    print(e);
  }
}

Future<void> readConfig() async {
  final config = File('po_editor.yaml');
  final content = await config.readAsString();
  final yaml = loadYaml(content);

  final languages = yaml['languages'];
  if (languages?.isNotEmpty == true) {
    supportedLocales.addAll([...languages!]);
  }

  poEditorApiProjectId = yaml['po_editor_project_id'];
  poEditorApiKey = yaml['po_editor_api_key'];
  fallbackLanguage = yaml['fallback'] ?? 'en';
  translationsDir = yaml['translations_dir'];
  output = yaml['output'];

  final platform = yaml['platform'];
  flutterEnabled = platform['flutter']?.toLowerCase() == 'copy';
  nativeAndroidEnabled = platform['android']?.toLowerCase() == 'copy';
  nativeIosEnabled = platform['ios']?.toLowerCase() == 'copy';
}

Future<String?> getLocaleFileUrl(String languageCode, String type) async {
  http.Response response = await http.post(Uri.parse(poEditorExportEndpoint),
    headers: <String, String>{
      'Content-Type' : 'application/x-www-form-urlencoded'
    },
    body: {
      'api_token' : poEditorApiKey,
      'id' : poEditorApiProjectId,
      'language' : languageCode,
      'type' : type,
      'filters' : 'translated'
    },
    encoding: Encoding.getByName("utf-8")
  );
  if (response.statusCode == 200) {
    final json = jsonDecode(response.body);
    if (json["response"]['status'] == 'success') {
      return json["result"]['url'];
    }
    print('Failed to export translation for $languageCode');
    return null;
  } else {
    throw Exception();
  }
}

Future<String> getLocalizationTranslation(String url) async {
  var request =  http.Request('GET', Uri.parse(url));
  var streamedResponse = await request.send();
  var response = await http.Response.fromStream(streamedResponse);
  if (response.statusCode == 200) {
    return response.body;
  } else {
    throw Exception();
  }
}

saveTranslationFile(String absoluteFileName, String content) async {
  var file = File(absoluteFileName);
  if (!await file.exists()) {
    await file.create();
  }
  await file.writeAsString(content);
}