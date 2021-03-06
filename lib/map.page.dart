import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:rightriding/menu.page.dart';
import 'BuildBikeInfra.dart';
import 'DirectionsProvider.dart';
import 'LocationOnMap.dart';
import 'Route.dart' as rou;
import 'package:geolocator/geolocator.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geoflutterfire/geoflutterfire.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rate_my_app/rate_my_app.dart';
import 'package:search_cep/search_cep.dart';

class MapPage extends StatefulWidget {
  @override
  _MapPageState createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  GoogleMapController mapController;
  CameraPosition _initialCameraPosition = CameraPosition(
    target: LatLng(-26.2903102, -48.8623476),
    zoom: 12,
  );
  Position _currentPosition = Position();

  Firestore firestore = Firestore.instance;
  Geoflutterfire geo = Geoflutterfire();
  final startAddressController = TextEditingController();
  final destinationAddressController = TextEditingController();
  RateMyApp _rateMyApp = RateMyApp(preferencesPrefix: 'RateMyApp_');
  StreamSubscription<Position> _locationChangeSubscription;
  StreamSubscription<Position> _stopSubscription;

  Position _startPosition;
  Position _destinationPosition;
  String _startAddress;
  String _destinationAddress;
  String _currentAddress;
  var _placeDistance;
  DateTime lastRateTime = DateTime.now();
  PolylinePoints polylinePoints = PolylinePoints();
  Set<Polyline> allPolylines = {};
  Map<PolylineId, Polyline> polylines = {};
  List<Marker> markers = [];
  DateTime startTime;

  rou.Route _currentRoute = rou.Route(id: 1);

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

  _getCurrentAddress() async {
    try {
      List<Placemark> p = await Geolocator().placemarkFromPosition(_currentPosition);
      Placemark place = p[0];
      ViaCepSearchCep cep = ViaCepSearchCep();
      final info = await cep.searchInfoByCep(cep: place.postalCode.replaceAll("-", ""), returnType: SearchInfoType.json);
      String streetName = info.fold((_) => null, (data) => data).logradouro;

      setState(() {
        _currentAddress = "$streetName, ${place.name}, ${place.postalCode}, ${place.country}";
        startAddressController.text = _currentAddress;
      });
    } catch (e) {
      print(e);
    }
  }

  _animateCamera(Position position) async {
    mapController.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(
      target: LatLng(position.latitude, position.longitude),
      zoom: 17.0,
    )));
  }

  _ratingDialog(int section, Position newPosition) {
    setState(() {
      lastRateTime = DateTime.now();
    });

    _rateMyApp.showStarRateDialog(
      context,
      title: 'O que voc?? achou do trecho que percorreu?',
      message: 'D?? uma nota:',
      actionsBuilder: (context, stars) {
        return [
          FlatButton(
            child: Text(
              'OK',
              style: GoogleFonts.montserrat(),
            ),
            onPressed: () {
              _addRatingToDatabase(section, newPosition, stars);
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

  void _listenToLocationChange(Position toPosition) {
    Geolocator _geolocatorChange = Geolocator();
    var distanceUntilDestiny = 1000.0;
    int section = 1;

    LocationOptions locationOptions = LocationOptions(accuracy: LocationAccuracy.best, timeInterval: 2000);
    Stream<Position> positionStream = _geolocatorChange.getPositionStream(locationOptions);
    _locationChangeSubscription = positionStream.listen((Position newPosition) async {

      LocationOnMap newLocation = LocationOnMap(position: newPosition, speed: newPosition.speed);
      newLocation.addToDatabase();

      _animateCamera(newPosition);
      distanceUntilDestiny = await _geolocatorChange.distanceBetween(newPosition.latitude, newPosition.longitude, toPosition.latitude, toPosition.longitude);

      setState(() {
        _placeDistance = distanceUntilDestiny;
      });

      if (distanceUntilDestiny < 20) {
        _ratingDialog(section, newPosition);
        _currentRoute.to = newPosition;
        _locationChangeSubscription.cancel();
        _stopSubscription.cancel();

        print("ARRIVED!! Subscription Cancelled");
        setState(() {
          //volte pro estado inicial da pagina
        });
      }
    });
  }

  void _listenToStop(Position toPosition) {
    int section = 1;
    Position last = _startPosition;
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
          _ratingDialog(section, newPosition);
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

  Future<DocumentReference> _addRatingToDatabase(int section, Position position, double stars) async {
    print("Rate added");
    GeoFirePoint endOfSection = geo.point(latitude: position.latitude, longitude: position.longitude);
    return firestore.collection('sections').add({
      'route': _currentRoute,
      'stars': stars,
      'section': section,
      'end_of_section': endOfSection.data,
      'average speed': '',
    });
  }

  int _getRouteName() {
    var routesRef = firestore.collection('Routes');
    return routesRef.orderBy('name').limit(1).hashCode;
  }

  dynamic _calculateDistance( dynamic _placeDistance) {
    if (_placeDistance == null) {
      return;
    }
    else {
      return _placeDistance.toStringAsPrecision(4);
    }
  }

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    allPolylines = BuildBikeInfra().build();
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
            Padding(
              padding: EdgeInsets.all(10.0),
              child: Icon(
                Icons.directions_bike,
                color: Colors.white,
              ),
            ),
          ],
        ),
        body: Stack(
          children: <Widget>[
            Consumer<DirectionProvider>(
              builder: (BuildContext context, DirectionProvider api, Widget child) {
                return GoogleMap(
                  initialCameraPosition: _initialCameraPosition,
                  myLocationButtonEnabled: false,
                  myLocationEnabled: true,
                  mapType: MapType.normal,
                  zoomGesturesEnabled: true,
                  zoomControlsEnabled: false,
                  markers: Set<Marker>.of(markers),
                  polylines: allPolylines,
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
                  padding: const EdgeInsets.only(top: 5.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white70,
                      borderRadius: BorderRadius.all(
                        Radius.circular(20.0),
                      ),
                    ),
                    width: width * 0.9,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 5.0, bottom: 5.0),
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
                          SizedBox(height: 3),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _textField(
                                  label: 'Origem',
                                  initialValue: '',
                                  controller: startAddressController,
                                  width: width * 0.832,
                                  locationCallback: (String value) {
                                    setState(() {

                                    });
                                  }),
                              SizedBox(width: 5),
                              SizedBox(
                                width: width * 0.132,
                                height: width * 0.132,
                                child: RaisedButton(
                                  onPressed: () {
                                    setState(() {
                                      _getCurrentLocation();
                                    });
                                  },
                                  padding: EdgeInsets.all(2.0),
                                  color: Colors.white,
                                  child: Icon(
                                    Icons.location_searching,
                                    size: 23,
                                    color: Colors.deepPurple,
                                  ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: new BorderRadius.circular(10.0),
                                      side: BorderSide(color: Colors.purple[100], width: 2.0),
                                    )
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 3),
                          _textField(
                              label: 'Destino',
                              initialValue: ' ',
                              controller: destinationAddressController,
                              width: width,
                              locationCallback: (String value) {
                                setState(() {
                                  _destinationAddress = value;
                                });
                              }),
                          SizedBox(height: 3),
                          Visibility(
                            visible: _placeDistance == null ? false : true,
                            child: Text(
                              'Distancia: ${_calculateDistance(_placeDistance)} m',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              RaisedButton(
                                onPressed: () async {
                                  Geolocator _geolocator = Geolocator();
                                  List<Placemark> destinationPlacemark = await _geolocator.placemarkFromAddress(_destinationAddress);
                                  _destinationPosition = Position(longitude: destinationPlacemark[0].position.longitude, latitude: destinationPlacemark[0].position.latitude);
                                  _placeDistance = await _geolocator.distanceBetween(_currentPosition.latitude, _currentPosition.longitude, _destinationPosition.latitude, _destinationPosition.longitude);
                                  var api = Provider.of<DirectionProvider>(context, listen: false);

                                  setState(() {
                                    allPolylines.addAll(api.currentRoute);
                                    api.findDirections(_currentPosition, _destinationPosition);
                                  });
                                },
                                color: Colors.deepPurple[200],
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20.0),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(1.0),
                                  child: Text(
                                    'Mostrar',
                                    style: TextStyle(
                                      color: Colors.deepPurple,
                                    ),
                                    textScaleFactor: 1,
                                  ),
                                ),
                              ),
                              SizedBox(width: 7),
                              RaisedButton(
                                onPressed: () async {
                                  Geolocator _geolocator = Geolocator();
                                  List<Placemark> destinationPlacemark = await _geolocator.placemarkFromAddress(_destinationAddress);
                                  _destinationPosition = Position(longitude: destinationPlacemark[0].position.longitude, latitude: destinationPlacemark[0].position.latitude);
                                  _startPosition = _currentPosition;
                                  _placeDistance = await _geolocator.distanceBetween(_startPosition.latitude, _startPosition.longitude, _destinationPosition.latitude, _destinationPosition.longitude);

                                  setState(() {
                                    startTime = DateTime.now();
                                    _currentRoute.id = _getRouteName() + 1;
                                    _currentRoute.from = _currentPosition;

                                    //cria se????o com inicio nesse ponto.

                                    _listenToLocationChange(_destinationPosition);
                                    _listenToStop(_destinationPosition);
                                  });
                                },
                                color: Colors.green[200],
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20.0),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(1.0),
                                  child: Text(
                                    'Iniciar',
                                    style: TextStyle(
                                      color: Colors.deepPurple,
                                    ),
                                    textScaleFactor: 1,
                                  ),
                                ),
                              ),
                              SizedBox(width: 7),
                              RaisedButton(
                                onPressed: () {
                                  setState(() {
                                    _currentRoute.to = _currentPosition;

                                    if (_locationChangeSubscription != null) {
                                      _locationChangeSubscription.cancel();
                                      _locationChangeSubscription = null;
                                    }
                                    if (_stopSubscription != null) {
                                      _stopSubscription.cancel();
                                      _stopSubscription = null;
                                    }
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) {
                                        return ChangeNotifierProvider(
                                          create: (_) => DirectionProvider(),
                                          child: MaterialApp(
                                            home: MainMenu(),
                                          ),
                                        );
                                      },
                                    ),
                                  );
                                  });},
                                color: Colors.red[200],
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20.0),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(1.0),
                                  child: Text(
                                    'Cancelar',
                                    style: TextStyle(
                                      color: Colors.deepPurple,
                                    ),
                                    textScaleFactor: 1,
                                  ),
                                ),
                              ),
                            ],
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
                        color: Colors.deepPurple[100], // button color
                        child: InkWell(
                          splashColor: Colors.deepPurple, // inkwell color
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
                        color: Colors.deepPurple[100], // button color
                        child: InkWell(
                          splashColor: Colors.deepPurple[400], // inkwell color
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
