import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  print('Fetching OurAirports data...');
  final url = Uri.parse(
    'https://davidmegginson.github.io/ourairports-data/airports.csv',
  );

  try {
    final client = HttpClient();
    final request = await client.getUrl(url);
    final response = await request.close();

    if (response.statusCode == 200) {
      final strData = await response.transform(utf8.decoder).join();
      final lines = strData.split('\n');

      final headers = lines[0].split(',');
      print('Headers: ${headers.join(", ")}');

      final validTypes = ['large_airport', 'medium_airport'];
      final List<Map<String, dynamic>> airports = [];

      for (int i = 1; i < lines.length; i++) {
        if (lines[i].trim().isEmpty) continue;

        // Basic CSV parsing handling quotes
        final values = _parseCsvLine(lines[i]);
        if (values.length >= 14) {
          final type = values[2].replaceAll('"', '');
          if (validTypes.contains(type)) {
            final iata = values[13].replaceAll('"', ''); // iata_code
            if (iata.trim().isEmpty)
              continue; // Skip airports without IATA code

            airports.add({
              'id': values[0].replaceAll('"', ''),
              'ident': values[1].replaceAll('"', ''),
              'type': type,
              'name': values[3].replaceAll('"', ''),
              'lat': double.tryParse(values[4].replaceAll('"', '')) ?? 0.0,
              'lon': double.tryParse(values[5].replaceAll('"', '')) ?? 0.0,
              'iso_country': values[8].replaceAll('"', ''),
              'iso_region': values[9].replaceAll('"', ''),
              'municipality': values[10].replaceAll('"', ''),
              'iata_code': iata,
              'local_code': values[14].replaceAll('"', ''),
            });
          }
        }
      }
      print('Parsed ${airports.length} major airports with IATA codes.');

      // Save it as JSON to assets
      final outDir = Directory('assets/data');
      if (!await outDir.exists()) {
        await outDir.create(recursive: true);
      }

      final outFile = File('assets/data/airports.json');
      await outFile.writeAsString(jsonEncode(airports));
      print('Saved to ${outFile.path}');
    } else {
      print('Failed to download: ${response.statusCode}');
    }
    client.close();
  } catch (e) {
    print('Error: $e');
  }
}

List<String> _parseCsvLine(String line) {
  final List<String> result = [];
  bool inQuotes = false;
  StringBuffer buffer = StringBuffer();

  for (int i = 0; i < line.length; i++) {
    final char = line[i];
    if (char == '"') {
      inQuotes = !inQuotes;
    } else if (char == ',' && !inQuotes) {
      result.add(buffer.toString());
      buffer.clear();
    } else {
      buffer.write(char);
    }
  }
  result.add(buffer.toString());
  return result;
}
