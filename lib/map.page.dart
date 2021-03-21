import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'DirectionsProvider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:location/location.dart' as loc;
import 'package:geoflutterfire/geoflutterfire.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rxdart/rxdart.dart';
import 'package:firebase_core/firebase_core.dart';

class MapPage extends StatefulWidget {
  @override
  _MapPageState createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  GoogleMapController mapController;
  CameraPosition _initialLocation = CameraPosition(
    target: LatLng(-26.2903102, -48.8623476),
    zoom: 13,
  );

  final Geolocator _geolocator = Geolocator();
  Firestore firestore = Firestore.instance;
  Geoflutterfire geo = Geoflutterfire();

  final startAddressController = TextEditingController();
  final destinationAddressController = TextEditingController();

  Position _currentPosition = Position();
  String _placeDistance = '';
  String _startAddress = '';
  String _destinationAddress = '';
  String _currentAddress = '';
  PolylinePoints polylinePoints = PolylinePoints();
  Map<PolylineId, Polyline> polylines = {};
  List<Marker> markers = [];

  Widget _textField({
    TextEditingController controller,
    String label,
    String hint,
    String initialValue,
    double width,
    Icon prefixIcon,
    Widget suffixIcon,
    Function(String) locationCallback,
  }) {
    return Container(
      width: width * 0.8,
      child: TextFormField(
        onChanged: (value) {
          locationCallback(value);
        },
        controller: controller,
        // initialValue: initialValue,
        decoration: new InputDecoration(
          prefixIcon: prefixIcon,
          suffixIcon: suffixIcon,
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(
              Radius.circular(10.0),
            ),
            borderSide: BorderSide(
              color: Colors.grey.shade400,
              width: 2,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(
              Radius.circular(10.0),
            ),
            borderSide: BorderSide(
              color: Colors.blue.shade300,
              width: 2,
            ),
          ),
          contentPadding: EdgeInsets.all(15),
          hintText: hint,
        ),
      ),
    );
  }

  _getCurrentLocation() async {
    await _geolocator
        .getCurrentPosition(desiredAccuracy: LocationAccuracy.high)
        .then((Position position) async {
      setState(() {
        _currentPosition = position;
        print('CURRENT POS: $_currentPosition');
        mapController.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(position.latitude, position.longitude),
              zoom: 18.0,
            ),
          ),
        );
      });
      await _getCurrentAddress();
    }).catchError((e) {
      print(e);
    });
  }

  Future<StreamSubscription>_listenToLocationChange(LatLng toPoint) async {
    var distanceUntilDestiny = 1000.0;

    StreamSubscription subscription = _geolocator
        .getPositionStream(
            LocationOptions(accuracy: LocationAccuracy.best, distanceFilter: 2))
        .listen((newPosition) async {
      _addPointToDatabase(newPosition);

      var cameraUpdate = CameraUpdate.newCameraPosition(CameraPosition(
        target: LatLng(newPosition.latitude, newPosition.longitude),
        zoom: 15,
      ));
      mapController.animateCamera(cameraUpdate);

      distanceUntilDestiny = await _geolocator.distanceBetween(
          newPosition.latitude,
          newPosition.longitude,
          toPoint.latitude,
          toPoint.longitude);
      //tesntar retornar a distancia.
      if (distanceUntilDestiny < 20) {
        print("ARRIVED!!");
        //PARAR DE MANDAR COISA P BANCO
      }
    });
    return subscription;
  }

  // _listenToArrival(LatLng toPoint) async {
  //   Position position;
  //   var distanceUntilDestiny = 1000.0;
  //
  //   while (distanceUntilDestiny > 5) {
  //     position = await _geolocator.getCurrentPosition(
  //         desiredAccuracy: LocationAccuracy.best);
  //     distanceUntilDestiny = await _geolocator.distanceBetween(
  //         position.latitude,
  //         position.longitude,
  //         toPoint.latitude,
  //         toPoint.longitude);
  //   }
  //   return true;
  // }

  // void _listenToLocationChange2(LatLng fromPoint, LatLng toPoint) async {
  //   Future<Position> position;
  //
  //   Future<double> distanceUntilDestiny =  _geolocator.distanceBetween(fromPoint.latitude, toPoint.longitude, toPoint.latitude, toPoint.longitude);
  //   while (distanceUntilDestiny > 5){
  //     position = _geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best)
  //     distanceUntilDestiny = _geolocator.distanceBetween(position.latitude, position.longitude, toPoint.latitude, toPoint.longitude);
  //   }
  // }

  Future<DocumentReference> _addPointToDatabase(Position position) async {
    GeoFirePoint point =
        geo.point(latitude: position.latitude, longitude: position.longitude);
    return firestore.collection('routes').add({
      'name': '1',
      'timestamp': position.timestamp,
      'position': point.data,
      'speed': position.speed
    });
  }

  _getCurrentAddress() async {
    try {
      List<Placemark> p = await _geolocator.placemarkFromCoordinates(
          _currentPosition.latitude, _currentPosition.longitude);

      Placemark place = p[0];

      setState(() {
        _currentAddress =
            "${place.name}, ${place.locality}, ${place.postalCode}, ${place.country}";
        print('CURRENT ADDRESS: $_currentAddress');
        startAddressController.text = _currentAddress;
        _startAddress = _currentAddress;
      });
    } catch (e) {
      print(e);
    }
  }

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    _getCurrentAddress();
    //_polylines = keyByPolylineId(widget.polylines);  botar as polylines da estrutur que pode começar aqui
  }

  @override
  Widget build(BuildContext context) {
    var height = MediaQuery.of(context).size.height;
    var width = MediaQuery.of(context).size.width;
    Set<Marker> markers = Set<Marker>();

    return Container(
      child: Scaffold(
        appBar: AppBar(
          title: Text("RightRiding"),
        ),
        body: Stack(
          children: <Widget>[
            Consumer<DirectionProvider>(
              builder:
                  (BuildContext context, DirectionProvider api, Widget child) {
                return GoogleMap(
                  initialCameraPosition: _initialLocation,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  mapType: MapType.normal,
                  zoomGesturesEnabled: true,
                  zoomControlsEnabled: false,
                  markers: Set<Marker>.of(markers),
                  polylines: api.currentRoute,
                  //posso add as polylines marcando ruas com infraestrutura cicloviaria bem clarinho
                  onMapCreated: (GoogleMapController controller) {
                    setState(() {
                      mapController = controller;
                    });
                  },
                );
              },
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 10.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white70,
                      borderRadius: BorderRadius.all(
                        Radius.circular(20.0),
                      ),
                    ),
                    width: width * 0.9,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10.0, bottom: 10.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            'Find Route',
                            style: TextStyle(fontSize: 20.0),
                          ),
                          SizedBox(height: 10),
                          _textField(
                              label: 'From',
                              initialValue: _currentAddress,
                              controller: startAddressController,
                              width: width,
                              locationCallback: (String value) {
                                setState(() {
                                  _startAddress = value;
                                });
                              }),
                          SizedBox(height: 10),
                          _textField(
                              label: 'To',
                              initialValue: '',
                              controller: destinationAddressController,
                              width: width,
                              locationCallback: (String value) {
                                setState(() {
                                  _destinationAddress = value;
                                });
                              }),
                          SizedBox(height: 10),
                          Visibility(
                            visible: _placeDistance == null ? false : true,
                            child: Text(
                              'DISTANCE: $_placeDistance km',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          SizedBox(height: 5),
                          RaisedButton(
                            onPressed: (_destinationAddress != '')
                                ? () async {
                                    List<Placemark> startPlacemark =
                                        await _geolocator.placemarkFromAddress(
                                            _startAddress);
                                    List<Placemark> destinationPlacemark =
                                        await _geolocator.placemarkFromAddress(
                                            _destinationAddress);

                                    var api = Provider.of<DirectionProvider>(
                                        context,
                                        listen: false);

                                    LatLng fromPoint = LatLng(
                                        startPlacemark[0].position.latitude,
                                        startPlacemark[0].position.longitude);
                                    LatLng toPoint = LatLng(
                                        destinationPlacemark[0]
                                            .position
                                            .latitude,
                                        destinationPlacemark[0]
                                            .position
                                            .longitude);

                                    setState(() {
                                      // _addMarker(fromPoint, "From");
                                      // _addMarker(toPoint, "To");
                                      _listenToLocationChange(toPoint);
                                      api.findDirections(
                                          _startAddress, _destinationAddress);

                                    });
                                  }
                                : null,
                            color: Colors.red,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20.0),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text(
                                'Show Route'.toUpperCase(),
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20.0,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(left: 10.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    ClipOval(
                      child: Material(
                        color: Colors.blue[100], // button color
                        child: InkWell(
                          splashColor: Colors.blue, // inkwell color
                          child: SizedBox(
                            width: 50,
                            height: 50,
                            child: Icon(Icons.add),
                          ),
                          onTap: () {
                            mapController.animateCamera(
                              CameraUpdate.zoomIn(),
                            );
                          },
                        ),
                      ),
                    ),
                    SizedBox(height: 20),
                    ClipOval(
                      child: Material(
                        color: Colors.blue[100], // button color
                        child: InkWell(
                          splashColor: Colors.blue, // inkwell color
                          child: SizedBox(
                            width: 50,
                            height: 50,
                            child: Icon(Icons.remove),
                          ),
                          onTap: () {
                            mapController.animateCamera(
                              CameraUpdate.zoomOut(),
                            );
                          },
                        ),
                      ),
                    )
                  ],
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 20.0, bottom: 20.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      ClipOval(
                        child: Material(
                          color: Colors.red[300], // button color
                          child: InkWell(
                            splashColor: Colors.red, // inkwell color
                            child: SizedBox(
                              width: 50,
                              height: 50,
                              child: Text("Report Event"),
                            ),
                            onTap: () {},
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

// void _addMarker(LatLng position, String label) {
//   final Marker marker = Marker(
//     markerId: markerId,
//     position: position,
//     infoWindow: InfoWindow(title: label),
//   );
//
//   setState(() {
//     markers.add(marker);
//   });
// }

// _animateToUser() async {
//   var pos = await location.getLocation();
//   mapController.animateCamera(CameraUpdate.newCameraPosition(
//       CameraPosition(
//         target: LatLng(pos['latitude'], pos['longitude']),
//         zoom: 17.0,
//       )
//   )
//   );
// }
}
