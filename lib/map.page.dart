import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'DirectionsProvider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geoflutterfire/geoflutterfire.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rate_my_app/rate_my_app.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';

class MapPage extends StatefulWidget {
  @override
  _MapPageState createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  GoogleMapController mapController;
  CameraPosition _initialLocation = CameraPosition(
    target: LatLng(-26.2903102, -48.8623476),
    zoom: 17,
  );

  Firestore firestore = Firestore.instance;
  Geoflutterfire geo = Geoflutterfire();
  final startAddressController = TextEditingController();
  final destinationAddressController = TextEditingController();
  RateMyApp _rateMyApp = RateMyApp(preferencesPrefix: 'RateMyApp_');

  Position _currentPosition = Position();
  Position _startPosition;
  Position _destinationPosition;
  String _startAddress = '';
  String _destinationAddress = ' ';
  String _currentAddress;
  var _placeDistance;
  DateTime lastRateTime = DateTime.now();

  PolylinePoints polylinePoints = PolylinePoints();
  Set<Polyline> allPolylines = {};
  Map<PolylineId, Polyline> polylines = {};

  List<Marker> markers = [];
  DateTime startTime;
  int route = 1;

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
              color: Colors.purple[100],
              width: 2,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(
              Radius.circular(10.0),
            ),
            borderSide: BorderSide(
              color: Colors.purple,
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
    await Geolocator().getCurrentPosition(desiredAccuracy: LocationAccuracy.high).then((Position position) async {
      setState(() {
        _currentPosition = position;
        _animateCamera(_currentPosition);
      });
      await _getCurrentAddress();
    }).catchError((e) {
      print(e);
    });
  }

  _animateCamera(Position position) async {
    mapController.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(
      target: LatLng(position.latitude, position.longitude),
      zoom: 17.0,
    )));
  }

  _ratingDialog(int route, int section, Position newPosition) {
    setState(() {
      lastRateTime = DateTime.now();
    });

    _rateMyApp.showStarRateDialog(
      context,
      title: 'O que você achou do trecho que percorreu?',
      message: 'Dê uma nota:',
      actionsBuilder: (context, stars) {
        return [
          FlatButton(
            child: Text(
              'OK',
              style: GoogleFonts.montserrat(),
            ),
            onPressed: () {
              _addRatingToDatabase(route, section, newPosition, stars);
              Navigator.pop(context);
            },
          ),
        ];
      },
      dialogStyle: const DialogStyle(
        dialogShape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(2.0))),
        titleAlign: TextAlign.center,
        messageAlign: TextAlign.center,
        messagePadding: EdgeInsets.only(bottom: 10),
      ),
      starRatingOptions: const StarRatingOptions(),
    );
  }

  StreamSubscription<Position> _locationChangeSubscription;
  StreamSubscription<Position> _stopSubscription;

  void _listenToLocationChange(int route, Position fromPosition, Position toPosition) {
    Geolocator _geolocatorChange = Geolocator();
    var distanceUntilDestiny = 1000.0;
    int section = 1;
    Position last = fromPosition;
    var delta = 10.0;
    Duration timeSinceDepart;

    LocationOptions locationOptions = LocationOptions(accuracy: LocationAccuracy.best, timeInterval: 2000);
    Stream<Position> positionStream = _geolocatorChange.getPositionStream(locationOptions);
    _locationChangeSubscription = positionStream.listen((Position newPosition) async {
      _addLocationToDatabase(newPosition);
      _animateCamera(newPosition);

      distanceUntilDestiny = await _geolocatorChange.distanceBetween(newPosition.latitude, newPosition.longitude, toPosition.latitude, toPosition.longitude);

      setState(() {
        _placeDistance = distanceUntilDestiny;
      });

      if (distanceUntilDestiny < 20) {
        _ratingDialog(route, section, newPosition);

        _locationChangeSubscription.cancel();
        _stopSubscription.cancel();
        print("ARRIVED!! Subscription Cancelled");
        setState(() {
          //volte pro estado inicial da pagina
        });
      }

      delta = await _geolocatorChange.distanceBetween(last.latitude, last.longitude, newPosition.latitude, newPosition.longitude);
    });
  }

  // distanceUntilDestiny(Position position1, Position position2, Geolocator _geolocation) async {
  //   var distance = await _geolocation.distanceBetween(position1.latitude, position1.longitude, position1.latitude, position1.longitude);
  //   return distance;
  // }

  void _listenToStop(int route, Position fromPosition, Position toPosition) {
    int section = 1;
    Position last = fromPosition;
    var delta = 10.0;
    Duration timeSinceDepart;
    Duration timeSinceLastRating;
    Geolocator _geolocatorStop = Geolocator();

    LocationOptions locationOptions = LocationOptions(accuracy: LocationAccuracy.best, timeInterval: 2000);
    Stream<Position> positionStream = _geolocatorStop.getPositionStream(locationOptions);

    _stopSubscription = positionStream.listen(
      (Position newPosition) async {
        delta = await _geolocatorStop.distanceBetween(last.latitude, last.longitude, newPosition.latitude, newPosition.longitude);

        timeSinceDepart = DateTime.now().difference(startTime);
        timeSinceLastRating = DateTime.now().difference(lastRateTime);

        if ((newPosition.speed < 1 || delta < 1) && (timeSinceDepart > Duration(seconds: 10)) && (timeSinceLastRating > Duration(seconds: 20))) {
          print("STOPPED!!");
          _ratingDialog(route, section, newPosition);
          setState(() {
            lastRateTime = DateTime.now();
          });
          section++;
        } else {
          last = newPosition;
        }
      },
    );
  }

  Future<DocumentReference> _addRatingToDatabase(int route, int section, Position position, double stars) async {
    print("Rate added");
    GeoFirePoint endOfSection = geo.point(latitude: position.latitude, longitude: position.longitude);
    return firestore.collection('sections').add({
      'route': route,
      'stars': stars,
      'section': section,
      'end_of_section': endOfSection.data,
      'average speed': '',
    });
  }

  Future<DocumentReference> _addLocationToDatabase(Position position) async {
    print("Location added");
    GeoFirePoint point = geo.point(latitude: position.latitude, longitude: position.longitude);
    return firestore.collection('routes').add({'name': route, 'timestamp': position.timestamp, 'position': point.data, 'speed': position.speed});
  }

  _getCurrentAddress() async {
    try {
      List<Placemark> p = await Geolocator().placemarkFromCoordinates(_currentPosition.latitude, _currentPosition.longitude);
      Placemark place = p[0];

      setState(() {
        _currentAddress = "${place.name}, ${place.locality}, ${place.postalCode}, ${place.country}";
        startAddressController.text = _currentAddress;
        _startAddress = _currentAddress;
        print(_currentAddress);
      });
    } catch (e) {
      print(e);
    }
  }

  int _getRouteName() {
    var routesRef = firestore.collection('routes');
    return routesRef.orderBy('name').limit(1).hashCode;
  }

  Map bikeLanes = {
    'polylineId': '',
     'polylineCoordinates': '',
  };

  List<LatLng> polylineCoordinates = [
    LatLng(-26.2170704,-48.8003377),
    LatLng(-26.2172218,-48.8000079),
    LatLng(-26.2172784,-48.7998866),
    LatLng(-26.2173748,-48.7996866),
    LatLng(-26.2174435,-48.7995542),
    LatLng(-26.2175059,-48.7994453),
    LatLng(-26.2175636,-48.7993522),
    LatLng(-26.2176454,-48.7992418),
  ];

  _addPolyLine(List<LatLng> polylineCoordinates) {
    print("added polyline");
    PolylineId id = PolylineId("poly");
    Polyline polyline = Polyline(
      polylineId: id,
      color: Colors.green,
      points: polylineCoordinates,
      width: 2,
    );
    polylines[id] = polyline;

    setState(() {
      allPolylines.add(polyline);
    });
  }


  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    _getCurrentAddress();
    _addPolyLine(polylineCoordinates);
  }

  @override
  Widget build(BuildContext context) {
    var height = MediaQuery.of(context).size.height;
    var width = MediaQuery.of(context).size.width;
    Set<Marker> markers = Set<Marker>();

    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: Text(
            "RR",
            textScaleFactor: 1.1,
            style: GoogleFonts.charmonman(
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: Colors.purple[800],
          toolbarHeight: 40,
          actions: <Widget>[
            Icon(Icons.directions_bike, color: Colors.white),
          ],
        ),
        body: Stack(
          children: <Widget>[
            Consumer<DirectionProvider>(
              builder: (BuildContext context, DirectionProvider api, Widget child) {
                return GoogleMap(
                  initialCameraPosition: _initialLocation,
                  myLocationEnabled: true,
                  mapType: MapType.normal,
                  zoomGesturesEnabled: true,
                  zoomControlsEnabled: false,
                  markers: Set<Marker>.of(markers),
                  polylines: allPolylines,
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
                            'Buscar Rota',
                            textScaleFactor: 1.2,
                            style: GoogleFonts.montserrat(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 5),
                          _textField(
                              label: 'Origem',
                              initialValue: _currentAddress,
                              controller: startAddressController,
                              width: width,
                              locationCallback: (String value) {
                                setState(() {
                                  _startAddress = value;
                                });
                              }),
                          SizedBox(height: 5),
                          _textField(
                              label: 'Destino',
                              initialValue: 'rua max colin 585',
                              controller: destinationAddressController,
                              width: width,
                              locationCallback: (String value) {
                                setState(() {
                                  _destinationAddress = value;
                                });
                              }),
                          SizedBox(height: 5),
                          Visibility(
                            visible: _placeDistance == null ? false : true,
                            child: Text(
                              'Distancia: $_placeDistance m',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          RaisedButton(
                            onPressed: () async {

                              Geolocator _geolocator = Geolocator();

                              List<Placemark> destinationPlacemark = await _geolocator.placemarkFromAddress(_destinationAddress);
                              List<Placemark> startPlacemark = await _geolocator.placemarkFromAddress(_startAddress);
                              _destinationPosition = Position(longitude: destinationPlacemark[0].position.longitude, latitude: destinationPlacemark[0].position.latitude);
                              _startPosition = Position(longitude: startPlacemark[0].position.longitude, latitude: startPlacemark[0].position.latitude);
                              _placeDistance = await _geolocator.distanceBetween(_startPosition.latitude, _startPosition.longitude, _destinationPosition.latitude, _destinationPosition.longitude);

                              var api = Provider.of<DirectionProvider>(context, listen: false);

                              setState(() {
                                allPolylines.addAll(api.currentRoute);

                                startTime = DateTime.now();
                                route = _getRouteName() + 1;

                                // _addMarker(fromPoint, "From");
                                // _addMarker(toPoint, "To");

                                api.findDirections(_startAddress, _destinationAddress);
                                _listenToLocationChange(route, _startPosition, _destinationPosition);

                                _listenToStop(route, _startPosition, _destinationPosition);
                              });
                            },
                            color: Colors.deepPurple[200],
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20.0),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(2.0),
                              child: Text(
                                'Mostrar Rota'.toUpperCase(),
                                style: TextStyle(
                                  color: Colors.deepPurple,
                                ),
                                textScaleFactor: 1,
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
                        color: Colors.pink[100], // button color
                        child: InkWell(
                          splashColor: Colors.pink, // inkwell color
                          child: SizedBox(
                            width: 40,
                            height: 40,
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
                    SizedBox(height: 15),
                    ClipOval(
                      child: Material(
                        color: Colors.pink[100], // button color
                        child: InkWell(
                          splashColor: Colors.pink[400], // inkwell color
                          child: SizedBox(
                            width: 40,
                            height: 40,
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
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    if (_locationChangeSubscription != null) {
      _locationChangeSubscription.cancel();
      _locationChangeSubscription = null;
    }
    if (_stopSubscription != null) {
      _stopSubscription.cancel();
      _stopSubscription = null;
    }
    super.dispose();
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

}
