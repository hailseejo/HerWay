import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

enum NearbyPlaceCategory { police, hospital, public }

class NearbyPlace {
  const NearbyPlace({
    required this.name,
    required this.category,
    required this.latitude,
    required this.longitude,
    required this.distanceMeters,
    this.openingHours,
  });

  final String name;
  final NearbyPlaceCategory category;
  final double latitude;
  final double longitude;
  final double distanceMeters;
  final String? openingHours;

  String get distanceLabel {
    final miles = distanceMeters / 1609.344;
    if (miles < 0.1) return '< 0.1 mi';
    return '${miles.toStringAsFixed(1)} mi';
  }

  String get categoryLabel {
    switch (category) {
      case NearbyPlaceCategory.police:
        return 'Police';
      case NearbyPlaceCategory.hospital:
        return 'Hospital';
      case NearbyPlaceCategory.public:
        return 'Public place';
    }
  }
}

class NearbyPlacesService {
  NearbyPlacesService({http.Client? client})
      : _client = client ?? http.Client();

  static final Uri _endpoint =
      Uri.parse('https://overpass-api.de/api/interpreter');
  final http.Client _client;

  Future<List<NearbyPlace>> fetchNearby(Position position) async {
    final query = '''
[out:json][timeout:20];
(
  nwr["amenity"~"^(police|hospital|fire_station|library|community_centre|social_centre|shelter|townhall)\$"](around:5000,${position.latitude},${position.longitude});
  nwr["public_transport"="station"](around:5000,${position.latitude},${position.longitude});
);
out center tags;
''';

    final response = await _client.get(
      _endpoint.replace(queryParameters: {'data': query}),
      headers: const {'User-Agent': 'HerWay safety app'},
    );
    if (response.statusCode != 200) {
      throw Exception('Nearby places service returned ${response.statusCode}.');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['elements'] is! List) {
      throw const FormatException('Nearby places response was invalid.');
    }

    final places = <NearbyPlace>[];
    for (final item in decoded['elements'] as List) {
      if (item is! Map<String, dynamic>) continue;
      final tags = item['tags'];
      if (tags is! Map<String, dynamic>) continue;
      final name = tags['name'];
      final coordinates = _coordinates(item);
      if (name is! String || name.trim().isEmpty || coordinates == null) {
        continue;
      }

      final category = _category(tags);
      if (category == null) continue;
      places.add(
        NearbyPlace(
          name: name.trim(),
          category: category,
          latitude: coordinates.$1,
          longitude: coordinates.$2,
          distanceMeters: Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            coordinates.$1,
            coordinates.$2,
          ),
          openingHours: tags['opening_hours'] as String?,
        ),
      );
    }

    places.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return places;
  }

  (double, double)? _coordinates(Map<String, dynamic> element) {
    final latitude = element['lat'] ?? (element['center'] as Map?)?['lat'];
    final longitude = element['lon'] ?? (element['center'] as Map?)?['lon'];
    if (latitude is! num || longitude is! num) return null;
    return (latitude.toDouble(), longitude.toDouble());
  }

  NearbyPlaceCategory? _category(Map<String, dynamic> tags) {
    if (tags['amenity'] == 'police') return NearbyPlaceCategory.police;
    if (tags['amenity'] == 'hospital') return NearbyPlaceCategory.hospital;
    if (tags['amenity'] == 'fire_station' ||
        tags['amenity'] == 'library' ||
        tags['amenity'] == 'community_centre' ||
        tags['amenity'] == 'social_centre' ||
        tags['amenity'] == 'shelter' ||
        tags['amenity'] == 'townhall' ||
        tags['public_transport'] == 'station') {
      return NearbyPlaceCategory.public;
    }
    return null;
  }

  void dispose() => _client.close();
}
