import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:geoflutterfire/geoflutterfire.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'Section.dart';

class Route {
  int id;
  Position from;
  Position to;
  List<Section> sections;
  double averageSpeed;
  double averageEvaluation;

  Firestore firestore = Firestore.instance;
  Geoflutterfire geo = Geoflutterfire();

  Route({
    this.id,
    this.from,
    this.to,
    this.sections,
    this.averageSpeed,
    this.averageEvaluation
  });

  Future<DocumentReference> addToDatabase() async {
    print("Route added");
    GeoFirePoint fromPoint = geo.point(latitude: from.latitude, longitude: from.longitude);
    GeoFirePoint toPoint = geo.point(latitude: to.latitude, longitude: to.longitude);
    return firestore.collection('Locations').add({'id': id, 'from': fromPoint, 'to': toPoint, 'sections': sections, 'averageSpeed': averageSpeed, 'averageEvaluation': averageEvaluation});
  }

  Section addSection() {
    Section section = Section(id: 1, routeId: this.id);
    this.sections.add(section);
    return section;
  }

  endSection() {

  }

  endRoute() {

  }

  cancel() {

  }
}