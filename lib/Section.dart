import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geoflutterfire/geoflutterfire.dart';
import 'package:geolocator/geolocator.dart';

class Section {
  final int id;
  final int routeId;
  final Position from;
  Position to;
  double stars;
  DateTime evaluationTimestamp;

  Firestore firestore = Firestore.instance;
  Geoflutterfire geo = Geoflutterfire();

  Section({
    this.id,
    this.routeId,
    this.from,
    this.to,
    this.stars,
    this.evaluationTimestamp,
  });

  Future<DocumentReference> addToDatabase() async {
    print("Section added");
    GeoFirePoint fromPoint = geo.point(latitude: from.latitude, longitude: from.longitude);
    GeoFirePoint toPoint = geo.point(latitude: to.latitude, longitude: to.longitude);
    return firestore.collection('Locations').add({'id': id, 'routeId': routeId, 'from': fromPoint, 'to': toPoint, 'stars': stars, 'evaluationTimestamp': evaluationTimestamp});
  }
}