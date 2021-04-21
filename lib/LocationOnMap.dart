import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geoflutterfire/geoflutterfire.dart';
import 'package:geolocator/geolocator.dart';

class LocationOnMap {
  final int routeId;
  final DateTime timestamp = DateTime.now();
  final Position position;
  final double speed;
  Firestore firestore = Firestore.instance;
  Geoflutterfire geo = Geoflutterfire();

  LocationOnMap({
    this.routeId,
    this.position,
    this.speed
  });

  Future<DocumentReference> addToDatabase() async {
    print("Location added");
    GeoFirePoint point = geo.point(latitude: position.latitude, longitude: position.longitude);
    return firestore.collection('Locations').add({'routeId': routeId, 'timestamp': timestamp, 'position': point.data, 'speed': speed});
  }
}
