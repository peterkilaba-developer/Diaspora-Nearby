import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// Decoded vehicle information from a VIN.
class VinDecodedData {
  final String? make;
  final String? model;
  final String? year;
  final String? trim;
  final String? series;
  final String? fuelType;
  final String? transmission;
  final String? bodyClass;
  final String? driveType;
  final String? engineCylinders;
  final String? displacementL;
  final String? engineHP;
  final String? engineConfiguration;
  final String? doors;
  final String? plantCountry;
  final String? plantCity;
  final String? vehicleType;
  final String? abs;
  final String? airbagLocations;
  final String? gvwr;
  final String? electrificationType;
  final String? batteryKWh;
  final String? errorMessage;

  const VinDecodedData({
    this.make,
    this.model,
    this.year,
    this.trim,
    this.series,
    this.fuelType,
    this.transmission,
    this.bodyClass,
    this.driveType,
    this.engineCylinders,
    this.displacementL,
    this.engineHP,
    this.engineConfiguration,
    this.doors,
    this.plantCountry,
    this.plantCity,
    this.vehicleType,
    this.abs,
    this.airbagLocations,
    this.gvwr,
    this.electrificationType,
    this.batteryKWh,
    this.errorMessage,
  });

  bool get isValid =>
      make != null &&
      make!.isNotEmpty &&
      model != null &&
      model!.isNotEmpty &&
      errorMessage == null;

  /// Formatted engine description e.g. "2.5L 4-cyl (203 hp)"
  String? get engineDescription {
    final parts = <String>[];
    if (displacementL != null) {
      final litres = double.tryParse(displacementL!);
      if (litres != null) {
        parts.add('${litres.toStringAsFixed(1)}L');
      }
    }
    if (engineCylinders != null) {
      parts.add('$engineCylinders-cyl');
    }
    if (engineHP != null) {
      parts.add('($engineHP hp)');
    }
    return parts.isEmpty ? null : parts.join(' ');
  }

  /// Compact engine label e.g. "1.5L I4", "3.0L V6", "4.4L V8"
  String? get compactEngineLabel {
    if (displacementL == null && engineCylinders == null) return null;
    final buf = StringBuffer();
    if (displacementL != null) {
      final litres = double.tryParse(displacementL!);
      if (litres != null) {
        buf.write('${litres.toStringAsFixed(1)}L ');
      }
    }
    if (engineCylinders != null) {
      final cyls = int.tryParse(engineCylinders!);
      if (cyls != null) {
        buf.write(_configPrefix(engineConfiguration, cyls));
        buf.write(cyls);
      }
    }
    final result = buf.toString().trim();
    return result.isEmpty ? null : result;
  }

  /// Derive short config prefix: 'I' for inline, 'V', 'F' for flat/boxer, 'W'
  static String _configPrefix(String? config, int cylinders) {
    if (config != null && config.isNotEmpty) {
      final lower = config.toLowerCase();
      if (lower.contains('in-line') ||
          lower.contains('inline') ||
          lower.contains('straight')) {
        return 'I';
      }
      if (lower.startsWith('v') || lower.contains('v-')) return 'V';
      if (lower.contains('flat') ||
          lower.contains('opposed') ||
          lower.contains('boxer')) {
        return 'F';
      }
      if (lower.startsWith('w')) return 'W';
      if (lower.contains('rotary')) return 'R';
    }
    // Smart default when config is missing
    return cylinders >= 6 ? 'V' : 'I';
  }
}

/// Service to decode VINs using the free NHTSA vPIC API.
///
/// Endpoint: https://vpic.nhtsa.dot.gov/api/vehicles/DecodeVinValues/{VIN}?format=json
/// No API key required. Works for most global manufacturers.
class VinDecoderService {
  static const _baseUrl =
      'https://vpic.nhtsa.dot.gov/api/vehicles/DecodeVinValues';

  static final Map<String, VinDecodedData> _cache = {};

  /// Synchronous 0ms lookup if this VIN was already decoded in this session.
  static VinDecodedData? getCached(String vin) =>
      _cache[vin.trim().toUpperCase()];

  /// Decodes a 17-character VIN and returns vehicle data.
  static Future<VinDecodedData> decode(String vin) async {
    final normalized = vin.trim().toUpperCase();
    if (normalized.length != 17) {
      return const VinDecodedData(
        errorMessage: 'VIN must be exactly 17 characters',
      );
    }

    final cached = _cache[normalized];
    if (cached != null) return cached;

    try {
      final url = Uri.parse('$_baseUrl/$normalized?format=json');
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return VinDecodedData(
          errorMessage: 'API error: ${response.statusCode}',
        );
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final results = json['Results'] as List<dynamic>?;

      if (results == null || results.isEmpty) {
        return const VinDecodedData(
          errorMessage: 'No data returned for this VIN',
        );
      }

      final data = results[0] as Map<String, dynamic>;

      // Check for NHTSA error codes
      final errorCode = _getString(data, 'ErrorCode');
      if (errorCode != null && errorCode != '0' && !errorCode.contains('0')) {
        final errorText = _getString(data, 'ErrorText');
        final make = _getString(data, 'Make');
        if (make == null || make.isEmpty) {
          return VinDecodedData(
            errorMessage: errorText ?? 'Could not decode this VIN',
          );
        }
      }

      final rawTransmission = _getString(data, 'TransmissionStyle');
      final rawDriveType = _getString(data, 'DriveType');
      debugPrint('[VIN] Raw TransmissionStyle: $rawTransmission');
      debugPrint('[VIN] Raw DriveType: $rawDriveType');

      final decoded = VinDecodedData(
        make: _getString(data, 'Make'),
        model: _getString(data, 'Model'),
        year: _getString(data, 'ModelYear'),
        trim: _getString(data, 'Trim'),
        series: _getString(data, 'Series'),
        fuelType: _mapFuelType(_getString(data, 'FuelTypePrimary')),
        transmission: _mapTransmission(rawTransmission),
        bodyClass: _mapBodyClass(_getString(data, 'BodyClass')),
        driveType: _mapDriveType(rawDriveType),
        engineCylinders: _getString(data, 'EngineCylinders'),
        displacementL: _getString(data, 'DisplacementL'),
        engineHP: _getString(data, 'EngineHP'),
        engineConfiguration: _getString(data, 'EngineConfiguration'),
        doors: _getString(data, 'Doors'),
        plantCountry: _getString(data, 'PlantCountry'),
        plantCity: _getString(data, 'PlantCity'),
        vehicleType: _getString(data, 'VehicleType'),
        abs: _getString(data, 'ABS'),
        airbagLocations: _getString(data, 'AirBagLocFront') != null
            ? [
                if (_getString(data, 'AirBagLocFront') != null)
                  'Front: ${_getString(data, 'AirBagLocFront')}',
                if (_getString(data, 'AirBagLocSide') != null)
                  'Side: ${_getString(data, 'AirBagLocSide')}',
                if (_getString(data, 'AirBagLocCurtain') != null)
                  'Curtain: ${_getString(data, 'AirBagLocCurtain')}',
                if (_getString(data, 'AirBagLocKnee') != null)
                  'Knee: ${_getString(data, 'AirBagLocKnee')}',
              ].join(', ')
            : null,
        gvwr: _getString(data, 'GVWR'),
        electrificationType: _getString(data, 'ElectrificationLevel'),
        batteryKWh: _getString(data, 'BatteryKWh'),
      );

      if (decoded.isValid) {
        _cache[normalized] = decoded;
      }
      return decoded;
    } catch (e) {
      debugPrint('VIN decode error: $e');
      return const VinDecodedData(
        errorMessage: 'Failed to connect. Check your internet.',
      );
    }
  }

  /// Extracts a non-empty string or returns null.
  static String? _getString(Map<String, dynamic> data, String key) {
    final value = data[key]?.toString().trim();
    if (value == null || value.isEmpty || value == 'Not Applicable') {
      return null;
    }
    return value;
  }

  /// Maps NHTSA fuel type strings to the app's fuel type options.
  static String? _mapFuelType(String? nhtsaFuel) {
    if (nhtsaFuel == null) return null;
    final lower = nhtsaFuel.toLowerCase();

    if (lower.contains('gasoline') || lower.contains('petrol')) {
      return 'Petrol';
    } else if (lower.contains('diesel')) {
      return 'Diesel';
    } else if (lower.contains('electric') && !lower.contains('hybrid')) {
      return 'Electric';
    } else if (lower.contains('hybrid') || lower.contains('plug-in')) {
      return 'Hybrid';
    } else if (lower.contains('lpg') ||
        lower.contains('propane') ||
        lower.contains('compressed natural')) {
      return 'LPG';
    }

    return null;
  }

  /// Maps NHTSA transmission strings to the app's options.
  static String? _mapTransmission(String? nhtsaTransmission) {
    if (nhtsaTransmission == null) return null;
    final lower = nhtsaTransmission.toLowerCase();

    if (lower.contains('cvt') || lower.contains('continuously variable')) {
      return 'CVT';
    }
    if (lower.contains('automatic') ||
        lower.contains('dual-clutch') ||
        lower.contains('dual clutch') ||
        lower.contains('dct') ||
        lower.contains('dsg') ||
        lower.contains('tiptronic') ||
        lower.contains('automated manual')) {
      return 'Automatic';
    }
    if (lower.contains('manual')) return 'Manual';

    debugPrint('[VIN] Unmapped transmission: $nhtsaTransmission');
    return null;
  }

  /// Maps NHTSA body class to standard types.
  static String? _mapBodyClass(String? nhtsaBody) {
    if (nhtsaBody == null) return null;
    final lower = nhtsaBody.toLowerCase();

    if (lower.contains('sedan') || lower.contains('saloon')) return 'Sedan';
    if (lower.contains('suv') || lower.contains('sport utility')) return 'SUV';
    if (lower.contains('hatchback')) return 'Hatchback';
    if (lower.contains('coupe') || lower.contains('coupé')) return 'Coupe';
    if (lower.contains('convertible') || lower.contains('cabriolet')) {
      return 'Convertible';
    }
    if (lower.contains('wagon') || lower.contains('estate')) return 'Wagon';
    if (lower.contains('pickup') || lower.contains('truck')) return 'Pickup';
    if (lower.contains('van') || lower.contains('minivan')) return 'Van';
    if (lower.contains('crossover')) return 'Crossover';

    return nhtsaBody;
  }

  static String? _mapDriveType(String? nhtsaDrive) {
    if (nhtsaDrive == null) return null;
    final lower = nhtsaDrive.toLowerCase();

    if (lower.contains('awd') ||
        lower.contains('all-wheel') ||
        lower.contains('all wheel')) {
      return 'AWD';
    }
    if (lower.contains('4wd') ||
        lower.contains('4x4') ||
        lower.contains('four-wheel') ||
        lower.contains('four wheel') ||
        lower.contains('4-wheel')) {
      return '4WD';
    }
    if (lower.contains('front')) return 'FWD';
    if (lower.contains('rear')) return 'RWD';
    if (lower == '4x2') return 'FWD';

    debugPrint('[VIN] Unmapped drive type: $nhtsaDrive');
    return nhtsaDrive;
  }
}
