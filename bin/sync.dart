// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:yaml/yaml.dart';

List<String> supportedLocales = [];
late String fallbackLanguage;
late String translationsDir;
late String output;

const poEditorExportEndpoint = 'https://api.poeditor.com/v2/projects/export';
late String poEditorApiKey;
late String poEditorApiProjectId;

void main(List<String> args) async {
  print('Export translations from PO Editor is started');

  try {
    await readConfig();

    for (final language in supportedLocales) {
      final url = await getLocaleFileUrl(language);
      if (url?.isNotEmpty == true) {
        print('Prepare to export $language from $url');
        String name = '$language.json';
        String translation = await getLocalizationTranslation(url!);
        if (translation.isNotEmpty) {
          saveTranslationFile(name, translation);
          print('Translation for $language has been updated.');
        }
      }
    }

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
}

Future<String?> getLocaleFileUrl(String languageCode) async {
  http.Response response = await http.post(Uri.parse(poEditorExportEndpoint),
    headers: <String, String>{
      'Content-Type' : 'application/x-www-form-urlencoded'
    },
    body: {
      'api_token' : poEditorApiKey,
      'id' : poEditorApiProjectId,
      'language' : languageCode,
      'type' : 'key_value_json',
      'filters' : 'translated',
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

saveTranslationFile(String fileName, String content) async {
  var file = File('$translationsDir$fileName');
  if (!await file.exists()) {
    await file.create();
  }
  await file.writeAsString(content);
}