import 'package:flutter_map/flutter_map.dart' show TileProvider;
import 'package:geolocator/geolocator.dart';

/// Where the phone is, for "Near me", or why it is not known.
class Located {
  const Located.at(double this.latitude, double this.longitude)
    : problem = null;
  const Located.failed(String this.problem) : latitude = null, longitude = null;

  final double? latitude;
  final double? longitude;

  /// Plain words for the person, when there is no position.
  final String? problem;
}

/// Asks the phone for its position. Only call it after the person tapped
/// Near me and saw why: this is where the permission prompt appears.
typedef Locate = Future<Located> Function();

/// The phone's position through `geolocator`, at about 100 m accuracy (all
/// "Near me" needs). The position is not stored or sent anywhere except as
/// the map's search area.
Future<Located> locateWithGeolocator() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const Located.failed(
        'Location is turned off on this phone. Turn it on in Settings, or move the map yourself.',
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      return const Located.failed(
        'Without your location the map stays where it is. You can still move it yourself.',
      );
    }
    if (permission == LocationPermission.deniedForever) {
      return const Located.failed(
        'Location is not allowed for RightProperty365. You can allow it in Settings, or move the map yourself.',
      );
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 15),
      ),
    );
    return Located.at(position.latitude, position.longitude);
  } on Exception {
    return const Located.failed(
      'We could not find where you are. Move the map yourself instead.',
    );
  }
}

/// A map tile source: the URL template and the attribution its provider
/// requires, shown on every map.
class MapTiles {
  const MapTiles({
    required this.urlTemplate,
    required this.attribution,
    this.tileProvider,
  });

  final String urlTemplate;
  final String attribution;

  /// Tests replace the network.
  final TileProvider? tileProvider;
}
