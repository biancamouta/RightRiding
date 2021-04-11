import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:rightriding/menu.page.dart';
import 'DirectionsProvider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geoflutterfire/geoflutterfire.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rate_my_app/rate_my_app.dart';

class MapPage extends StatefulWidget {
  @override
  _MapPageState createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  GoogleMapController mapController;
  CameraPosition _initialLocation = CameraPosition(
    target: LatLng(-26.2903102, -48.8623476),
    zoom: 12,
  );

  Firestore firestore = Firestore.instance;
  Geoflutterfire geo = Geoflutterfire();
  final startAddressController = TextEditingController();
  final destinationAddressController = TextEditingController();
  RateMyApp _rateMyApp = RateMyApp(preferencesPrefix: 'RateMyApp_');
  StreamSubscription<Position> _locationChangeSubscription;
  StreamSubscription<Position> _stopSubscription;
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

  Set<Polyline> _buildAllBikeInfra() {
    Set<Polyline> all = {};

    allPoints.forEach((element) {
      List<LatLng> polylineCoordinates = _buildPoints(element);
      Polyline polyline = _buildPolyLine(polylineCoordinates);
      polylines[polyline.polylineId] = polyline;
      all.add(polyline);
    });

    print(all);
    return all;
  }

  List<LatLng> _buildPoints(var polyline) {
    List<LatLng> points = [];

    polyline.forEach((element) {
      points.add(LatLng(element[1], element[0]));
    });

    return points;
  }

  Polyline _buildPolyLine(List<LatLng> polylineCoordinates) {
    PolylineId id = PolylineId(DateTime.now().toString());

    Polyline polyline = Polyline(
      polylineId: id,
      color: Colors.green,
      points: polylineCoordinates,
      width: 3,
    );

    return polyline;
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
    _getCurrentAddress();
    allPolylines = _buildAllBikeInfra();
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
                  initialCameraPosition: _initialLocation,
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
                                  initialValue: _currentAddress,
                                  controller: startAddressController,
                                  width: width * 0.832,
                                  locationCallback: (String value) {
                                    setState(() {
                                      _startAddress = value;
                                    });
                                  }),
                              SizedBox(width: 5),
                              SizedBox(
                                width: width * 0.132,
                                height: width * 0.132,
                                child: RaisedButton(
                                  onPressed: () {
                                    setState(() {
                                      _getCurrentAddress();
                                      Future<Position> position = _getCurrentLocation();
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
                                  _startPosition = _currentPosition;
                                  _placeDistance = await _geolocator.distanceBetween(_startPosition.latitude, _startPosition.longitude, _destinationPosition.latitude, _destinationPosition.longitude);
                                  var api = Provider.of<DirectionProvider>(context, listen: false);

                                  setState(() {
                                    startTime = DateTime.now();
                                    route = _getRouteName() + 1;
                                    // _addMarker(fromPoint, "From");
                                    // _addMarker(toPoint, "To");
                                    allPolylines.addAll(api.currentRoute);
                                    api.findDirections(_startPosition, _destinationPosition);
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
                                    _listenToLocationChange(route, _startPosition, _destinationPosition);
                                    _listenToStop(route, _startPosition, _destinationPosition);
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

  var allPoints = [
    [
      [-48.8887383, -26.2826746],
      [-48.887414, -26.2830012],
      [-48.8872383, -26.2830518],
      [-48.8871411, -26.2830853],
      [-48.8870688, -26.2831121],
      [-48.886953, -26.2831632],
      [-48.8868512, -26.2832129],
      [-48.8867558, -26.2832665],
      [-48.8866399, -26.2833403],
      [-48.8864202, -26.2834941],
      [-48.8857836, -26.2839596],
      [-48.8855739, -26.2841113],
      [-48.8855056, -26.2841579],
      [-48.8854264, -26.284204],
      [-48.885351, -26.2842386],
      [-48.885241, -26.2842763],
      [-48.8851202, -26.2843024],
      [-48.8849738, -26.284325],
      [-48.8847671, -26.2843489],
      [-48.8846712, -26.2843575],
      [-48.8845538, -26.2843646],
      [-48.8844227, -26.2843719],
      [-48.8825361, -26.2844603]
    ],
    [
      [-48.8003377, -26.2170704],
      [-48.8000079, -26.2172218],
      [-48.7998866, -26.2172784],
      [-48.7996866, -26.2173748],
      [-48.7995542, -26.2174435],
      [-48.7994453, -26.2175059],
      [-48.7993522, -26.2175636],
      [-48.7992418, -26.2176454],
      [-48.7990955, -26.2177674],
      [-48.7990077, -26.2178436],
      [-48.7989471, -26.217902],
      [-48.7989055, -26.2179474],
      [-48.798867, -26.2180054],
      [-48.7988403, -26.2180547],
      [-48.7988238, -26.2180935]
    ],
    [
      [-48.8613238, -26.3144764],
      [-48.8609763, -26.3141164],
      [-48.8608447, -26.3139785],
      [-48.8607751, -26.3139096],
      [-48.8607285, -26.3138661],
      [-48.8606759, -26.3138223],
      [-48.8606295, -26.3137866],
      [-48.8605829, -26.3137507]
    ],
    [
      [-48.8539065, -26.3209743],
      [-48.8540632, -26.320901],
      [-48.8544367, -26.3205949],
      [-48.855001, -26.3201204],
      [-48.8563444, -26.3189824],
      [-48.8574318, -26.3180478],
      [-48.8575096, -26.3179802],
      [-48.8577036, -26.3178117],
      [-48.8579702, -26.3175759],
      [-48.8580491, -26.3175012],
      [-48.8584034, -26.3171757]
    ],
    [
      [-48.8314216, -26.2730155],
      [-48.8337778, -26.2704288],
      [-48.8341119, -26.270056],
      [-48.8355314, -26.2684724]
    ],
    [
      [-48.8382023, -26.2831422],
      [-48.8375216, -26.2828952],
      [-48.8364446, -26.2825044],
      [-48.8354976, -26.2821607],
      [-48.834534, -26.281811]
    ],
    [
      [-48.8535241, -26.2892731],
      [-48.8535624, -26.2893121],
      [-48.8535921, -26.2893605],
      [-48.8536108, -26.2894102],
      [-48.8536494, -26.2898318],
      [-48.853711, -26.290579],
      [-48.8537582, -26.2911297],
      [-48.8538426, -26.292114]
    ],
    [
      [-48.8646355, -26.2937144],
      [-48.865544, -26.2936536],
      [-48.8664401, -26.2935935]
    ],
    [
      [-48.8335429, -26.2752678],
      [-48.8342066, -26.2748471],
      [-48.8347923, -26.2744758],
      [-48.8353745, -26.2741067],
      [-48.8359102, -26.2737671],
      [-48.836502, -26.2733919],
      [-48.8367005, -26.2732561],
      [-48.8368474, -26.2731465],
      [-48.8370509, -26.2729751],
      [-48.8382824, -26.2718044],
      [-48.8388886, -26.271232],
      [-48.8396476, -26.2705153]
    ],
    [
      [-48.8368508, -26.2776206],
      [-48.8371842, -26.2775762],
      [-48.8372679, -26.2775708],
      [-48.8373845, -26.2775774],
      [-48.8374685, -26.2775942],
      [-48.8375736, -26.2776307]
    ],
    [
      [-48.8409291, -26.2774652],
      [-48.8412202, -26.2770517],
      [-48.8414217, -26.2767653],
      [-48.8416215, -26.2764945],
      [-48.8425784, -26.2751221]
    ],
    [
      [-48.8458865, -26.2719195],
      [-48.8471664, -26.2723768],
      [-48.8491078, -26.2730704]
    ],
    [
      [-48.8112439, -26.2773689],
      [-48.8112691, -26.2770229],
      [-48.8112828, -26.2768349],
      [-48.8113104, -26.2764572],
      [-48.811329, -26.2762015],
      [-48.811375, -26.2755699],
      [-48.8113978, -26.2752576],
      [-48.8114651, -26.2743027]
    ],
    [
      [-48.8242152, -26.2716249],
      [-48.8241185, -26.2715652],
      [-48.8240752, -26.2715442],
      [-48.8240275, -26.2715251],
      [-48.8239558, -26.2715037],
      [-48.8238916, -26.2714919],
      [-48.8237933, -26.2714867],
      [-48.8236942, -26.2714972],
      [-48.8236008, -26.2715176]
    ],
    [
      [-48.8272303, -26.271431],
      [-48.8273133, -26.2714812],
      [-48.8276141, -26.2716723],
      [-48.8277439, -26.2717502],
      [-48.8279426, -26.2718763]
    ],
    [
      [-48.8245149, -26.2743237],
      [-48.8238141, -26.2750702],
      [-48.8230497, -26.2758844],
      [-48.8229471, -26.2759937],
      [-48.8224824, -26.2764888],
      [-48.8220219, -26.2769793]
    ],
    [
      [-48.8226312, -26.2715247],
      [-48.8224493, -26.2712519]
    ],
    [
      [-48.8455404, -26.3034973],
      [-48.8452608, -26.3035071],
      [-48.8451386, -26.3035113],
      [-48.8449131, -26.3035193],
      [-48.8445961, -26.3035304],
      [-48.8444587, -26.3035352],
      [-48.8441465, -26.3035461],
      [-48.8438218, -26.3035575],
      [-48.8437517, -26.30356]
    ],
    [
      [-48.851637, -26.3068107],
      [-48.8527588, -26.30575],
      [-48.852825, -26.3056874]
    ],
    [
      [-48.8500012, -26.3086533],
      [-48.8499357, -26.3085999],
      [-48.8499108, -26.3085353],
      [-48.849917, -26.3084787],
      [-48.8499455, -26.30841]
    ],
    [
      [-48.798683, -26.2829962],
      [-48.7985728, -26.2830422],
      [-48.7973818, -26.2835393],
      [-48.7964353, -26.2839345],
      [-48.7962778, -26.2840002],
      [-48.7946751, -26.2846692],
      [-48.7938477, -26.2850146],
      [-48.7937669, -26.2850448],
      [-48.7936961, -26.2850687],
      [-48.7936155, -26.2850881],
      [-48.7935333, -26.2851002],
      [-48.7934574, -26.285106],
      [-48.7933683, -26.285106],
      [-48.7922355, -26.285087]
    ],
    [
      [-48.8092403, -26.2844975],
      [-48.8089305, -26.2844529]
    ],
    [
      [-48.8025349, -26.2241991],
      [-48.8026354, -26.2243188],
      [-48.8026884, -26.2244584],
      [-48.8027072, -26.2246268],
      [-48.8026864, -26.2247513],
      [-48.8026161, -26.2249283],
      [-48.8024639, -26.2250793]
    ],
    [
      [-48.8024639, -26.2250793],
      [-48.8024557, -26.2251387],
      [-48.8024571, -26.2251748],
      [-48.8024705, -26.2252176],
      [-48.8025084, -26.2253056]
    ],
    [
      [-48.8013674, -26.2248403],
      [-48.8019508, -26.2244626],
      [-48.8019651, -26.2244439],
      [-48.8019723, -26.224422],
      [-48.8019535, -26.2243477]
    ],
    [
      [-48.8025084, -26.2253056],
      [-48.8024163, -26.2252321],
      [-48.8023572, -26.2252073],
      [-48.8022633, -26.2251965]
    ],
    [
      [-48.8075661, -26.2813879],
      [-48.8072873, -26.2811847],
      [-48.8070053, -26.2809791],
      [-48.8064156, -26.2805493],
      [-48.8058513, -26.2801379],
      [-48.8053017, -26.2797373],
      [-48.8047287, -26.2793196],
      [-48.8041591, -26.2789044],
      [-48.8036026, -26.2784988],
      [-48.8030577, -26.2781016]
    ],
    [
      [-48.8117016, -26.2710908],
      [-48.811413, -26.2706828],
      [-48.811212, -26.2703988],
      [-48.8108711, -26.2699169]
    ],
    [
      [-48.8596939, -26.266131],
      [-48.8601438, -26.2656215],
      [-48.8603822, -26.2653632],
      [-48.8612677, -26.2643643]
    ],
    [
      [-48.8749142, -26.2738527],
      [-48.8749184, -26.2739207],
      [-48.8749929, -26.2751248],
      [-48.8749972, -26.2751942],
      [-48.8750816, -26.276558],
      [-48.8751461, -26.2776623],
      [-48.8752164, -26.2787359],
      [-48.8752274, -26.2788156],
      [-48.8753414, -26.2793467],
      [-48.8753903, -26.2795831]
    ],
    [
      [-48.868099, -26.2925398],
      [-48.8663699, -26.29265],
      [-48.865484, -26.2927064],
      [-48.8645741, -26.2927644]
    ],
    [
      [-48.8416626, -26.3145481],
      [-48.8416451, -26.3151712]
    ],
    [
      [-48.8273167, -26.3081902],
      [-48.8272951, -26.3080676],
      [-48.8273091, -26.3079832],
      [-48.8273364, -26.307913],
      [-48.8273696, -26.3078721],
      [-48.8274121, -26.307827],
      [-48.8275565, -26.3077004]
    ],
    [
      [-48.8302314, -26.3186921],
      [-48.8306942, -26.3191826],
      [-48.8311507, -26.3196671],
      [-48.8316181, -26.3201637],
      [-48.8320573, -26.3206298],
      [-48.8325086, -26.3211088],
      [-48.8326066, -26.3212108]
    ],
    [
      [-48.8451355, -26.3190399],
      [-48.8452935, -26.3190476]
    ],
    [
      [-48.8256663, -26.3202591],
      [-48.8256996, -26.3202248],
      [-48.8257358, -26.3201876],
      [-48.8259864, -26.3199301],
      [-48.8264638, -26.3194394],
      [-48.8269408, -26.3189492],
      [-48.8272807, -26.3185998],
      [-48.8285184, -26.3173275]
    ],
    [
      [-48.8844384, -26.2964989],
      [-48.8843754, -26.2965575],
      [-48.8843308, -26.2966007],
      [-48.8843023, -26.2966329],
      [-48.8842541, -26.2966984],
      [-48.8842144, -26.2967693]
    ],
    [
      [-48.8079006, -26.3252608],
      [-48.8078209, -26.3251834],
      [-48.8077338, -26.3251246],
      [-48.8072722, -26.3249283],
      [-48.8068047, -26.3247295]
    ],
    [
      [-48.838771, -26.3618368],
      [-48.8386474, -26.3618566],
      [-48.8385938, -26.3618652],
      [-48.8383973, -26.3618967],
      [-48.8383599, -26.3619027],
      [-48.8379825, -26.3619679],
      [-48.8378625, -26.3619881],
      [-48.8376008, -26.362034],
      [-48.8374886, -26.3620471],
      [-48.8373943, -26.3620485],
      [-48.837316, -26.3620359],
      [-48.8372486, -26.3620084],
      [-48.8371899, -26.3619727],
      [-48.8370276, -26.3618504],
      [-48.8367628, -26.3616533],
      [-48.8365123, -26.3614836],
      [-48.8363462, -26.3614076],
      [-48.8362469, -26.3613657],
      [-48.8361477, -26.3613302],
      [-48.8360181, -26.3612964],
      [-48.8358422, -26.3612608],
      [-48.8353671, -26.3611887],
      [-48.8350011, -26.3611331],
      [-48.8349274, -26.3611206],
      [-48.8348355, -26.3610971],
      [-48.8347616, -26.3610714],
      [-48.8346865, -26.3610401],
      [-48.8345058, -26.3609658],
      [-48.8337941, -26.3606733],
      [-48.833691, -26.360638],
      [-48.8335772, -26.3606049],
      [-48.8334459, -26.3605787],
      [-48.8332951, -26.3605592],
      [-48.8328846, -26.3605319],
      [-48.8326454, -26.3605167],
      [-48.8324559, -26.3604995],
      [-48.8322456, -26.3604748],
      [-48.8320803, -26.3604646],
      [-48.8318849, -26.3604621]
    ],
    [
      [-48.7995814, -26.3396414],
      [-48.7993503, -26.3397899],
      [-48.799191, -26.339916],
      [-48.7989326, -26.340137],
      [-48.7988118, -26.3402491],
      [-48.7986704, -26.3403779],
      [-48.798524, -26.3405169],
      [-48.7982987, -26.3407504],
      [-48.7980458, -26.3410277],
      [-48.7979268, -26.3411669],
      [-48.7977047, -26.3414411],
      [-48.797592, -26.3415681],
      [-48.7974634, -26.3416906],
      [-48.7973614, -26.3417698],
      [-48.7972381, -26.3418562],
      [-48.797114, -26.3419243],
      [-48.7969776, -26.341974],
      [-48.7968629, -26.3420049],
      [-48.7964799, -26.3420778],
      [-48.7961325, -26.3421353],
      [-48.7958216, -26.3421872],
      [-48.7956548, -26.3422151],
      [-48.795555, -26.3422331],
      [-48.7954655, -26.3422558],
      [-48.7953921, -26.3422819],
      [-48.7953282, -26.3423154],
      [-48.7952582, -26.3423719],
      [-48.7950075, -26.3426391],
      [-48.7949438, -26.3427088],
      [-48.7944308, -26.3432703]
    ],
    [
      [-48.9039309, -26.1508369],
      [-48.9039317, -26.150748],
      [-48.9039452, -26.1506418],
      [-48.903961, -26.1505664],
      [-48.9039904, -26.1504808],
      [-48.9040207, -26.1504061],
      [-48.9040586, -26.1503362],
      [-48.9045007, -26.1496563],
      [-48.9045584, -26.1495666],
      [-48.9045989, -26.1494844],
      [-48.9046245, -26.1494121]
    ],
    [
      [-48.8452617, -26.3164289],
      [-48.8442454, -26.3163735],
      [-48.8426287, -26.3162855]
    ],
    [
      [-48.8543562, -26.3084456],
      [-48.8537967, -26.3085352],
      [-48.8537282, -26.3085451],
      [-48.853659, -26.3085698],
      [-48.853605, -26.3086042],
      [-48.8526396, -26.3095565],
      [-48.8526019, -26.3095945],
      [-48.8525185, -26.3096776],
      [-48.8524023, -26.3097883],
      [-48.8516449, -26.3105312],
      [-48.8516332, -26.3105427],
      [-48.8511474, -26.3110259],
      [-48.8507405, -26.3114335],
      [-48.8506892, -26.311469],
      [-48.8506485, -26.3114876]
    ],
    [
      [-48.832187, -26.2762193],
      [-48.8318735, -26.2759699],
      [-48.8317387, -26.2758789],
      [-48.8316104, -26.2757985],
      [-48.8311276, -26.2755387],
      [-48.8302621, -26.2749713],
      [-48.8299031, -26.2747452]
    ],
    [
      [-48.8390206, -26.267087],
      [-48.839185, -26.2679856],
      [-48.8393333, -26.2687946],
      [-48.8394486, -26.2694274],
      [-48.8396476, -26.2705153]
    ],
    [
      [-48.8306333, -26.3258726],
      [-48.8305607, -26.3258204]
    ],
    [
      [-48.8314533, -26.3258199],
      [-48.8311847, -26.3258656],
      [-48.8308838, -26.3259222]
    ],
    [
      [-48.8050451, -26.3146129],
      [-48.8047701, -26.3150012],
      [-48.8044891, -26.3153979],
      [-48.804204, -26.3158004],
      [-48.8039261, -26.3161928],
      [-48.8036444, -26.3165905],
      [-48.8035578, -26.316707],
      [-48.8034944, -26.3168029],
      [-48.8034513, -26.3168818],
      [-48.8034094, -26.3169717],
      [-48.8033834, -26.3170361],
      [-48.8033613, -26.3171216],
      [-48.8033489, -26.3172143],
      [-48.8033448, -26.3173086],
      [-48.8033516, -26.3174139],
      [-48.8033666, -26.3175356],
      [-48.803387, -26.3176181],
      [-48.8034224, -26.3177166],
      [-48.8034624, -26.3177949],
      [-48.8035088, -26.317868],
      [-48.8037224, -26.3182044],
      [-48.8039794, -26.3186093]
    ],
    [
      [-48.8635419, -26.283355],
      [-48.8634182, -26.283308],
      [-48.8632936, -26.2832729],
      [-48.8632032, -26.283263],
      [-48.863111, -26.2832683],
      [-48.8630264, -26.2832883],
      [-48.8629437, -26.2833225],
      [-48.8628777, -26.2833665]
    ],
    [
      [-48.8548435, -26.2987574],
      [-48.8545428, -26.2987943],
      [-48.8542133, -26.2988302],
      [-48.8535346, -26.2988776]
    ],
    [
      [-48.8625478, -26.2638652],
      [-48.8626381, -26.2638641],
      [-48.8631965, -26.2638569],
      [-48.8634554, -26.2638535],
      [-48.8638332, -26.2638475],
      [-48.8642871, -26.2638398],
      [-48.8644257, -26.2638327],
      [-48.8645544, -26.2638192],
      [-48.8647124, -26.2637913],
      [-48.8648396, -26.263761],
      [-48.8650972, -26.263692],
      [-48.8658074, -26.2635016],
      [-48.8659848, -26.2634702],
      [-48.8661281, -26.2634535],
      [-48.8662426, -26.2634473],
      [-48.8663353, -26.2634477],
      [-48.8664334, -26.2634497],
      [-48.8672477, -26.2634714],
      [-48.8673609, -26.2634822],
      [-48.8674494, -26.263495]
    ],
    [
      [-48.8596939, -26.266131],
      [-48.8597932, -26.2661737],
      [-48.8604342, -26.2664359],
      [-48.8606016, -26.2665049],
      [-48.8607328, -26.2665631],
      [-48.8608216, -26.2666042],
      [-48.8608845, -26.2666349],
      [-48.8609332, -26.266661],
      [-48.860986, -26.2666917],
      [-48.8610432, -26.2667282],
      [-48.861129, -26.2667883]
    ],
    [
      [-48.8616005, -26.263549],
      [-48.8610042, -26.263315],
      [-48.8593824, -26.2626786],
      [-48.8593231, -26.2626576],
      [-48.8592, -26.2626162],
      [-48.8590743, -26.262578],
      [-48.8587853, -26.2624988],
      [-48.8585956, -26.2624439],
      [-48.8584261, -26.2623892],
      [-48.8583269, -26.2623526],
      [-48.8582434, -26.2623172],
      [-48.8581053, -26.2622525],
      [-48.8579161, -26.2621536],
      [-48.8563503, -26.2612487],
      [-48.8557686, -26.2609125],
      [-48.8555021, -26.2607585],
      [-48.8552175, -26.2606003],
      [-48.8550073, -26.2604913],
      [-48.854806, -26.2603935],
      [-48.8545787, -26.260308],
      [-48.8544239, -26.2602582],
      [-48.8542005, -26.260201],
      [-48.8540724, -26.2601715],
      [-48.8540373, -26.2601635],
      [-48.8538368, -26.2601173],
      [-48.8535997, -26.2600628],
      [-48.8519508, -26.2597067]
    ],
    [
      [-48.8040646, -26.3596795],
      [-48.8033306, -26.3597148],
      [-48.8029181, -26.3597346],
      [-48.8027182, -26.359751],
      [-48.8025008, -26.3597738],
      [-48.8023623, -26.3597888],
      [-48.802255, -26.3597931],
      [-48.8021091, -26.3597825]
    ],
    [
      [-48.864814, -26.2964745],
      [-48.8646285, -26.2965046],
      [-48.8642815, -26.2965609]
    ],
    [
      [-48.8676505, -26.2961281],
      [-48.8673992, -26.2961515],
      [-48.86726, -26.296158],
      [-48.8671917, -26.2961511],
      [-48.8671404, -26.2961411],
      [-48.8669953, -26.2960944],
      [-48.8667, -26.2959931],
      [-48.8666172, -26.2959754],
      [-48.866534, -26.2959657],
      [-48.8664472, -26.2959704],
      [-48.8663592, -26.2959796],
      [-48.8662807, -26.2959915],
      [-48.866152, -26.2960179],
      [-48.866027, -26.29605],
      [-48.8659153, -26.2960844],
      [-48.8657819, -26.2961293],
      [-48.865703, -26.2961615],
      [-48.8655291, -26.2962461],
      [-48.8653047, -26.2963702],
      [-48.8652175, -26.2963984],
      [-48.8651363, -26.2964169],
      [-48.8650389, -26.2964354],
      [-48.864814, -26.2964745]
    ],
    [
      [-48.8516864, -26.2746684],
      [-48.8532198, -26.2747371],
      [-48.8545107, -26.2747949],
      [-48.8552933, -26.27483],
      [-48.8566743, -26.2748918],
      [-48.8599003, -26.2750363],
      [-48.8606012, -26.2750677],
      [-48.8614572, -26.2751061],
      [-48.8623252, -26.275145],
      [-48.8623565, -26.2751464],
      [-48.8626998, -26.2751618]
    ],
    [
      [-48.8313017, -26.3370867],
      [-48.8312097, -26.3371635],
      [-48.8311644, -26.3372074],
      [-48.8311218, -26.3372518],
      [-48.8310813, -26.3373061],
      [-48.83105, -26.3373614],
      [-48.8310246, -26.337419],
      [-48.8310113, -26.3374901],
      [-48.8310158, -26.3375845],
      [-48.8310381, -26.3376641],
      [-48.8310706, -26.3377398],
      [-48.8311615, -26.3379164],
      [-48.8311877, -26.3379742],
      [-48.8312188, -26.3380559],
      [-48.8312674, -26.3381866]
    ],
    [
      [-48.8092737, -26.3161976],
      [-48.8091508, -26.3161879],
      [-48.8090527, -26.3161803],
      [-48.8089657, -26.3161718],
      [-48.8088795, -26.3161553],
      [-48.8088016, -26.316128],
      [-48.8087122, -26.316087],
      [-48.8085795, -26.3160172],
      [-48.8080068, -26.3156879],
      [-48.8066851, -26.3149345],
      [-48.8060828, -26.3145942],
      [-48.8053503, -26.314182]
    ],
    [
      [-48.8013796, -26.3147636],
      [-48.8000845, -26.3155934],
      [-48.7989228, -26.3163343],
      [-48.7977326, -26.3170795],
      [-48.7976856, -26.3171048],
      [-48.7976471, -26.317115],
      [-48.7975746, -26.3171204],
      [-48.7975209, -26.3171145],
      [-48.7969064, -26.3169544]
    ],
    [
      [-48.8226286, -26.3345499],
      [-48.8221206, -26.3347623],
      [-48.8219347, -26.334839],
      [-48.821208, -26.3351387],
      [-48.8208112, -26.3353023],
      [-48.8206586, -26.3353654],
      [-48.8199209, -26.3356704],
      [-48.8191888, -26.3359733],
      [-48.8188765, -26.3362083],
      [-48.8185392, -26.3364621],
      [-48.8182286, -26.3366959],
      [-48.8180475, -26.3368321],
      [-48.8179569, -26.3369026],
      [-48.8178357, -26.3370037],
      [-48.817151, -26.33761]
    ],
    [
      [-48.8257304, -26.3385195],
      [-48.8255934, -26.3386531],
      [-48.8254677, -26.3387646],
      [-48.8251558, -26.339028],
      [-48.8251078, -26.3390688]
    ],
    [
      [-48.8136206, -26.3401393],
      [-48.813088, -26.3399563]
    ],
    [
      [-48.8223905, -26.3330735],
      [-48.8216799, -26.3332251],
      [-48.8201749, -26.3335461],
      [-48.8190835, -26.3337789],
      [-48.8190014, -26.3337964]
    ],
    [
      [-48.8475205, -26.3173141],
      [-48.8452237, -26.3172147]
    ],
    [
      [-48.847418, -26.3195895],
      [-48.845114, -26.3194866]
    ],
    [
      [-48.8466715, -26.3303478],
      [-48.8467375, -26.3303496],
      [-48.8493138, -26.330418]
    ],
    [
      [-48.832391, -26.3157273],
      [-48.8324145, -26.3156582],
      [-48.8324456, -26.3156105],
      [-48.8325107, -26.3142162],
      [-48.832642, -26.3142164]
    ],
    [
      [-48.8453159, -26.3220192],
      [-48.8455887, -26.3219907],
      [-48.8456378, -26.3219562],
      [-48.8456984, -26.3219251],
      [-48.8457617, -26.3219078],
      [-48.845876, -26.3219171],
      [-48.8459779, -26.3218944],
      [-48.8462998, -26.3217949],
      [-48.8463644, -26.3217656],
      [-48.846418, -26.3217298],
      [-48.8464644, -26.3217037],
      [-48.846523, -26.3216893],
      [-48.8466077, -26.3216831],
      [-48.8466804, -26.3216828],
      [-48.8467445, -26.3216763],
      [-48.8478288, -26.3213275],
      [-48.8481224, -26.3212124],
      [-48.8481882, -26.3211334]
    ],
    [
      [-48.8842144, -26.2967693],
      [-48.8842001, -26.2968768],
      [-48.8841853, -26.2969871],
      [-48.8841655, -26.2970887],
      [-48.8837357, -26.2997933],
      [-48.8837012, -26.300066],
      [-48.8835877, -26.3009617],
      [-48.8834818, -26.3014048],
      [-48.8832661, -26.3021087],
      [-48.8831162, -26.3024633],
      [-48.8828769, -26.3029311],
      [-48.8827316, -26.3032152],
      [-48.8826847, -26.3033069],
      [-48.8789205, -26.3090405],
      [-48.8784495, -26.3096768],
      [-48.8778576, -26.3103874],
      [-48.8772833, -26.3108333],
      [-48.8763263, -26.311516],
      [-48.8751278, -26.31231],
      [-48.8744066, -26.3128181],
      [-48.8742049, -26.3130247],
      [-48.8740321, -26.3133087],
      [-48.8739457, -26.3136014],
      [-48.8738832, -26.3139285],
      [-48.8738544, -26.3142211],
      [-48.8738448, -26.3150733],
      [-48.8737536, -26.3162654],
      [-48.8736768, -26.3165107],
      [-48.8736096, -26.3166312],
      [-48.8734127, -26.3169411],
      [-48.8723631, -26.3182669],
      [-48.8721436, -26.3185436],
      [-48.8720055, -26.3187215],
      [-48.8719483, -26.3187942],
      [-48.8718427, -26.318925],
      [-48.8681771, -26.3234752],
      [-48.8680592, -26.3235686]
    ],
    [
      [-48.8474958, -26.337827],
      [-48.8464087, -26.3378284],
      [-48.8463166, -26.3378303],
      [-48.8461556, -26.3378351],
      [-48.8460008, -26.3378394],
      [-48.8459231, -26.3378448],
      [-48.8458605, -26.3378541],
      [-48.8457838, -26.3378655],
      [-48.8456836, -26.3378891],
      [-48.8455347, -26.337929],
      [-48.8454315, -26.3379601],
      [-48.8450596, -26.338079],
      [-48.844226, -26.3383653]
    ],
    [
      [-48.8414931, -26.3393309],
      [-48.8415007, -26.3391837],
      [-48.8415172, -26.338863],
      [-48.8415268, -26.3386768],
      [-48.8415539, -26.3381519],
      [-48.8415879, -26.3374924],
      [-48.8415955, -26.337344],
      [-48.8416329, -26.3366179],
      [-48.841644, -26.336404],
      [-48.8416711, -26.3358777],
      [-48.8416805, -26.3356949]
    ],
    [
      [-48.8395209, -26.3617188],
      [-48.8393077, -26.3588979],
      [-48.8392794, -26.3586226],
      [-48.8392379, -26.3583596],
      [-48.8391381, -26.3578895],
      [-48.8390879, -26.3576355],
      [-48.8390501, -26.3573693],
      [-48.8390268, -26.3571576],
      [-48.8389147, -26.3559585],
      [-48.8388903, -26.3557406],
      [-48.8388578, -26.3555347],
      [-48.8388141, -26.3552351],
      [-48.8387336, -26.3546679]
    ],
    [
      [-48.8551352, -26.3072135],
      [-48.8551444, -26.3072951],
      [-48.8551416, -26.3073816],
      [-48.8551303, -26.3074787],
      [-48.8551093, -26.3075951],
      [-48.8550864, -26.3076735],
      [-48.8550564, -26.307735],
      [-48.8550098, -26.3078075],
      [-48.8549224, -26.307939],
      [-48.8546547, -26.3083244]
    ],
    [
      [-48.8643523, -26.2976536],
      [-48.8644469, -26.2991126],
      [-48.8645048, -26.3000055]
    ],
    [
      [-48.84697, -26.3482132],
      [-48.8469293, -26.3489853],
      [-48.8469276, -26.3490351],
      [-48.8469281, -26.3490876],
      [-48.8469318, -26.3491903],
      [-48.8469442, -26.3492848],
      [-48.8469672, -26.34938],
      [-48.8469914, -26.3494459],
      [-48.8470322, -26.3495285],
      [-48.8477206, -26.3505866],
      [-48.8477836, -26.3507093],
      [-48.84782, -26.3508159],
      [-48.8478537, -26.3509483],
      [-48.8478709, -26.3510579],
      [-48.8478808, -26.3511715],
      [-48.8478765, -26.3512712],
      [-48.8478672, -26.3513747],
      [-48.8478487, -26.3514839],
      [-48.8478142, -26.3516258],
      [-48.8477862, -26.3517149],
      [-48.8477252, -26.3518791],
      [-48.8476413, -26.3520683],
      [-48.847551, -26.352237],
      [-48.8473507, -26.3526038],
      [-48.8472317, -26.3528133],
      [-48.847142, -26.3529628]
    ],
    [
      [-48.8368892, -26.3660816],
      [-48.838335, -26.367876],
      [-48.8387054, -26.368329],
      [-48.8391793, -26.3689261]
    ],
    [
      [-48.8424143, -26.3638484],
      [-48.84256, -26.3644952],
      [-48.842805, -26.3655154],
      [-48.8431705, -26.3670188]
    ],
    [
      [-48.842201, -26.3607714],
      [-48.8426638, -26.3621019],
      [-48.8427115, -26.3621872],
      [-48.8427738, -26.3622657],
      [-48.8429243, -26.3623986],
      [-48.8430058, -26.3624778],
      [-48.8430472, -26.3625231],
      [-48.8430754, -26.3625687],
      [-48.8430963, -26.3626289],
      [-48.8430923, -26.3626881],
      [-48.8430686, -26.3627829],
      [-48.8429058, -26.3632334],
      [-48.8427034, -26.3638345]
    ],
    [
      [-48.8208923, -26.3714216],
      [-48.8216978, -26.3713696],
      [-48.8218862, -26.3713574],
      [-48.8224125, -26.3713234],
      [-48.8238416, -26.3712312],
      [-48.824281, -26.3712028],
      [-48.8244365, -26.3711927],
      [-48.8252173, -26.3711423],
      [-48.8262744, -26.3711089]
    ],
    [
      [-48.9084379, -26.3252063],
      [-48.9084545, -26.3250764],
      [-48.9084705, -26.3249864],
      [-48.9084978, -26.3248909],
      [-48.9085927, -26.3245455],
      [-48.9086062, -26.3244001],
      [-48.9086042, -26.324241],
      [-48.9085907, -26.3240115],
      [-48.9085982, -26.3238833],
      [-48.9086265, -26.3237489],
      [-48.9086664, -26.3236345],
      [-48.9087223, -26.3235433],
      [-48.9088147, -26.3234394],
      [-48.909608, -26.3226669],
      [-48.9102843, -26.3220077]
    ],
    [
      [-48.8453149, -26.300731],
      [-48.8453237, -26.3008387],
      [-48.845387, -26.3016121],
      [-48.8454561, -26.3024636],
      [-48.8454595, -26.3025049],
      [-48.8454652, -26.3025752]
    ],
    [
      [-48.8454652, -26.3025752],
      [-48.8454948, -26.3029384],
      [-48.8454987, -26.3029856],
      [-48.8455295, -26.3033634],
      [-48.8455355, -26.3034375],
      [-48.8455404, -26.3034973],
      [-48.8455584, -26.3037181]
    ],
    [
      [-48.8460684, -26.3057975],
      [-48.8461219, -26.3058069],
      [-48.8461155, -26.3058332]
    ],
    [
      [-48.832487, -26.3157325],
      [-48.832391, -26.3157273],
      [-48.831408, -26.3156737]
    ],
    [
      [-48.8475544, -26.3165539],
      [-48.8474575, -26.3165486],
      [-48.846905, -26.3165185],
      [-48.8452617, -26.3164289]
    ],
    [
      [-48.8424174, -26.3208518],
      [-48.8425071, -26.3189125]
    ],
    [
      [-48.8425071, -26.3189125],
      [-48.8425468, -26.3180564],
      [-48.8425661, -26.3176383],
      [-48.8425738, -26.3174714],
      [-48.8425821, -26.3172926],
      [-48.8426287, -26.3162855]
    ],
    [
      [-48.8407424, -26.3111121],
      [-48.8406453, -26.311108],
      [-48.8397049, -26.3110689],
      [-48.8396593, -26.311067],
      [-48.8395802, -26.3110637],
      [-48.8394701, -26.3110591],
      [-48.8394215, -26.3110571],
      [-48.8390073, -26.3110398],
      [-48.8386125, -26.3110234],
      [-48.8378083, -26.3109899]
    ],
    [
      [-48.842864, -26.3112005],
      [-48.8429059, -26.3102958],
      [-48.8429091, -26.3102263],
      [-48.8429398, -26.3095636],
      [-48.8429591, -26.3091466]
    ],
    [
      [-48.8356535, -26.3109002],
      [-48.835635, -26.3113752],
      [-48.8356204, -26.3117489],
      [-48.8355922, -26.31247],
      [-48.8355877, -26.3125843]
    ],
    [
      [-48.9025274, -26.2873784],
      [-48.9028808, -26.2873293],
      [-48.9030843, -26.287301],
      [-48.9034758, -26.2872465],
      [-48.9035753, -26.2872327],
      [-48.9045148, -26.2871021],
      [-48.9048404, -26.2870568],
      [-48.9049419, -26.2870427],
      [-48.9055172, -26.2869627],
      [-48.9056445, -26.286945],
      [-48.9066491, -26.2868053],
      [-48.9067232, -26.286795]
    ],
    [
      [-48.8231229, -26.3404636],
      [-48.8227841, -26.3406131],
      [-48.8225738, -26.3407041],
      [-48.8222585, -26.3408351],
      [-48.822194, -26.3408616],
      [-48.8220183, -26.3409271],
      [-48.8218866, -26.3409605],
      [-48.821755, -26.3409819],
      [-48.821576, -26.3409926]
    ],
    [
      [-48.8285211, -26.3607218],
      [-48.8283423, -26.3607385],
      [-48.8282723, -26.3607349],
      [-48.828208, -26.3607253],
      [-48.828114, -26.360693],
      [-48.8280607, -26.3606654],
      [-48.8277556, -26.360494],
      [-48.8275841, -26.3604085],
      [-48.8274652, -26.36037],
      [-48.8273296, -26.3603532],
      [-48.8272024, -26.3603614],
      [-48.8271185, -26.3603804],
      [-48.8270005, -26.3604179],
      [-48.8268898, -26.3604702],
      [-48.8266939, -26.3605844],
      [-48.8266649, -26.3606013],
      [-48.8263547, -26.3607854],
      [-48.8260062, -26.3609954],
      [-48.8258583, -26.36109],
      [-48.825727, -26.3611789],
      [-48.8256061, -26.3612709],
      [-48.8254962, -26.36136],
      [-48.8253796, -26.3614587],
      [-48.8252582, -26.3615742],
      [-48.8251084, -26.3617239],
      [-48.824975, -26.3618646],
      [-48.8248144, -26.3620345],
      [-48.8246732, -26.3621804],
      [-48.8245267, -26.3623221],
      [-48.8244072, -26.3624285],
      [-48.8242761, -26.3625369],
      [-48.8241424, -26.3626311],
      [-48.8240255, -26.3626988],
      [-48.8239472, -26.362736]
    ],
    [
      [-48.8239472, -26.362736],
      [-48.8238258, -26.3627806],
      [-48.8237313, -26.362808],
      [-48.8236605, -26.3628239],
      [-48.8233843, -26.3628696],
      [-48.8232339, -26.3628904],
      [-48.8229871, -26.3629252],
      [-48.8226627, -26.3629692],
      [-48.8225572, -26.3629762],
      [-48.8224403, -26.3629693],
      [-48.8223386, -26.3629455],
      [-48.8222546, -26.3629138],
      [-48.8221917, -26.3628841],
      [-48.8221208, -26.362843],
      [-48.8219425, -26.3627241],
      [-48.8216472, -26.3625277],
      [-48.8215768, -26.3624833],
      [-48.82149, -26.3624358],
      [-48.8213698, -26.3623839],
      [-48.8212507, -26.3623421],
      [-48.821133, -26.3623113],
      [-48.8207231, -26.3622272],
      [-48.8205484, -26.3621914],
      [-48.8200882, -26.3621049],
      [-48.8198993, -26.3620518],
      [-48.8197912, -26.3620053],
      [-48.8195135, -26.3618604],
      [-48.8193985, -26.3618064],
      [-48.8193297, -26.361789],
      [-48.8192557, -26.3617803],
      [-48.8191459, -26.3617734],
      [-48.8184209, -26.3617766]
    ],
    [
      [-48.8506834, -26.300431],
      [-48.8495849, -26.3004924],
      [-48.8494275, -26.3005012],
      [-48.8493538, -26.3005053],
      [-48.849171, -26.3005155],
      [-48.8479078, -26.3005861]
    ],
    [
      [-48.8530968, -26.3122674],
      [-48.8541871, -26.3112225],
      [-48.854347, -26.3110693],
      [-48.8545962, -26.3108305]
    ],
    [
      [-48.8190867, -26.3867047],
      [-48.8181337, -26.3877094],
      [-48.8180143, -26.3878309],
      [-48.8178957, -26.3879673],
      [-48.8178104, -26.3880764],
      [-48.817733, -26.3881897],
      [-48.8176376, -26.3883482],
      [-48.8175395, -26.3885303],
      [-48.8174623, -26.3886907],
      [-48.8173045, -26.3890457],
      [-48.817102, -26.3895351]
    ],
    [
      [-48.8605829, -26.3137507],
      [-48.8605183, -26.3137078],
      [-48.8604396, -26.3136618],
      [-48.8603807, -26.313631],
      [-48.8603157, -26.313598],
      [-48.860255, -26.3135704],
      [-48.8601903, -26.3135451],
      [-48.8601227, -26.3135212],
      [-48.8600606, -26.3135011]
    ],
    [
      [-48.8274298, -26.3773742],
      [-48.8266056, -26.3780825]
    ],
    [
      [-48.8266056, -26.3780825],
      [-48.8264146, -26.3782466],
      [-48.8250132, -26.3794508],
      [-48.8247563, -26.3796716],
      [-48.8245992, -26.3798203],
      [-48.8245185, -26.3799068],
      [-48.8244256, -26.3800142],
      [-48.8243335, -26.3801317],
      [-48.8242172, -26.3802981],
      [-48.8240966, -26.3804888],
      [-48.8239663, -26.3807091],
      [-48.8232733, -26.3819454]
    ],
    [
      [-48.8201099, -26.385668],
      [-48.8190867, -26.3867047]
    ],
    [
      [-48.8232733, -26.3819454],
      [-48.8229729, -26.3824715],
      [-48.8229493, -26.3825129],
      [-48.8228078, -26.3827409],
      [-48.8226808, -26.3829236],
      [-48.8225617, -26.3830834],
      [-48.8225419, -26.3831088],
      [-48.8223961, -26.3832919],
      [-48.8222615, -26.3834423],
      [-48.8221248, -26.3835841],
      [-48.821804, -26.3839168],
      [-48.8201099, -26.385668]
    ],
    [
      [-48.8468745, -26.3265858],
      [-48.8471327, -26.3265911],
      [-48.847738, -26.3266034]
    ],
    [
      [-48.8502084, -26.3420071],
      [-48.8508127, -26.342019],
      [-48.8508624, -26.3420312],
      [-48.8517744, -26.3425937]
    ],
    [
      [-48.8512406, -26.2717507],
      [-48.8518222, -26.271182],
      [-48.8524781, -26.2705343],
      [-48.8525951, -26.2704237],
      [-48.8526677, -26.2703595],
      [-48.8527375, -26.2702965],
      [-48.852843, -26.2702221],
      [-48.8529989, -26.270127],
      [-48.8531346, -26.2700533],
      [-48.8537355, -26.2697456],
      [-48.8539475, -26.2696421],
      [-48.8542221, -26.2695112],
      [-48.8548191, -26.2692419],
      [-48.8557836, -26.2688303],
      [-48.8564316, -26.2685577],
      [-48.8572149, -26.2682253],
      [-48.8574601, -26.2681201],
      [-48.8576492, -26.2680376],
      [-48.8577785, -26.2679717],
      [-48.8578845, -26.2679101],
      [-48.8579769, -26.2678473],
      [-48.8580708, -26.2677688],
      [-48.8581529, -26.2676931],
      [-48.8583299, -26.2675151],
      [-48.8586483, -26.2671936],
      [-48.858753, -26.2670863],
      [-48.8592399, -26.2666067],
      [-48.859293, -26.2665523],
      [-48.8594739, -26.2663669],
      [-48.8595922, -26.2662443],
      [-48.8596939, -26.266131]
    ],
    [
      [-48.8421403, -26.2954741],
      [-48.8422603, -26.2954819]
    ],
    [
      [-48.8435181, -26.2841562],
      [-48.8436115, -26.2841573],
      [-48.8436693, -26.2841579],
      [-48.8438782, -26.2842787],
      [-48.8439365, -26.2843094],
      [-48.8439498, -26.2843118],
      [-48.8439639, -26.2843031],
      [-48.8446665, -26.2834852],
      [-48.8447214, -26.2834281],
      [-48.84475, -26.2833915],
      [-48.8448054, -26.2833416],
      [-48.844831, -26.2832654],
      [-48.8448434, -26.2832337],
      [-48.845939, -26.2816958],
      [-48.8476781, -26.2789392],
      [-48.848407, -26.2774256],
      [-48.8487519, -26.2766927],
      [-48.8490079, -26.2759023],
      [-48.8490605, -26.2757408],
      [-48.8491136, -26.2755535],
      [-48.849156, -26.2753472],
      [-48.8492516, -26.2747538],
      [-48.8492835, -26.2746808],
      [-48.8493224, -26.2746269],
      [-48.8493423, -26.2745634]
    ],
    [
      [-48.8493423, -26.2745634],
      [-48.8487884, -26.2745432],
      [-48.8487327, -26.2745388],
      [-48.8486691, -26.2745221]
    ],
    [
      [-48.8441813, -26.2832249],
      [-48.8441847, -26.2833197],
      [-48.8441187, -26.2833122],
      [-48.8440271, -26.2833112],
      [-48.8439922, -26.2833125],
      [-48.8439747, -26.2833216],
      [-48.8439586, -26.2833426],
      [-48.8439452, -26.2833642],
      [-48.8439033, -26.2834314],
      [-48.8438726, -26.2834628],
      [-48.84381, -26.2835046],
      [-48.8436621, -26.2835974],
      [-48.8435501, -26.2836654]
    ],
    [
      [-48.8199727, -26.2776009],
      [-48.8198652, -26.2775274],
      [-48.8196901, -26.2774031]
    ],
    [
      [-48.8168831, -26.2764512],
      [-48.8169129, -26.2763944],
      [-48.8170471, -26.2762416],
      [-48.8171418, -26.2762048],
      [-48.8176919, -26.2756287]
    ],
    [
      [-48.8176919, -26.2756287],
      [-48.8179519, -26.2757983],
      [-48.8180967, -26.2767591]
    ],
    [
      [-48.8307966, -26.3156404],
      [-48.830637, -26.3157291],
      [-48.8305089, -26.3157291],
      [-48.8303896, -26.3157449],
      [-48.8302615, -26.3157687],
      [-48.8301599, -26.3158202],
      [-48.8300671, -26.3158835],
      [-48.8295899, -26.3163667],
      [-48.8294397, -26.3165924],
      [-48.8294044, -26.3166954],
      [-48.829369, -26.3168102],
      [-48.8293735, -26.3169884],
      [-48.8293558, -26.317131],
      [-48.8293204, -26.3172538],
      [-48.8292897, -26.3174621],
      [-48.8293223, -26.3175421],
      [-48.8294265, -26.3176498],
      [-48.8294305, -26.3177443],
      [-48.8295413, -26.3178795],
      [-48.8296562, -26.3179349],
      [-48.8301069, -26.3183824],
      [-48.8301201, -26.3184695],
      [-48.8302085, -26.3185765],
      [-48.8302314, -26.3186921]
    ],
    [
      [-48.828526, -26.3161748],
      [-48.8284244, -26.3160822],
      [-48.8283087, -26.3159311],
      [-48.8282336, -26.3157449],
      [-48.8284103, -26.3145885],
      [-48.828381, -26.314513],
      [-48.8283254, -26.3144594],
      [-48.8282039, -26.3144433],
      [-48.8281396, -26.3144437],
      [-48.828072, -26.3144843],
      [-48.8280697, -26.3145496],
      [-48.8281004, -26.3145854],
      [-48.8281532, -26.3146007],
      [-48.8280296, -26.3154026],
      [-48.8280215, -26.3156776],
      [-48.8280613, -26.3159786],
      [-48.8281231, -26.316232],
      [-48.8281143, -26.3163548],
      [-48.8281277, -26.3163863],
      [-48.8281673, -26.3164023],
      [-48.8282613, -26.316369],
      [-48.8283035, -26.3163527],
      [-48.828385, -26.3163045],
      [-48.8284176, -26.3162747],
      [-48.8284895, -26.3162121],
      [-48.828526, -26.3161748]
    ],
    [
      [-48.8284549, -26.3129241],
      [-48.8284909, -26.3130368]
    ],
    [
      [-48.8281532, -26.3146007],
      [-48.8281611, -26.3145529]
    ],
    [
      [-48.824805, -26.3089829],
      [-48.8249728, -26.3093314],
      [-48.8251948, -26.3097647],
      [-48.8253769, -26.3099953],
      [-48.8256937, -26.3102588],
      [-48.8268153, -26.3111596],
      [-48.8268958, -26.3112077]
    ],
    [
      [-48.8284909, -26.3130368],
      [-48.8282926, -26.3145815]
    ],
    [
      [-48.8282926, -26.3145815],
      [-48.8282066, -26.3152848],
      [-48.8281959, -26.3154483],
      [-48.8281932, -26.3155781],
      [-48.8282039, -26.3156575],
      [-48.8282336, -26.3157449]
    ],
    [
      [-48.828375, -26.3130097],
      [-48.828457, -26.312455]
    ],
    [
      [-48.8281611, -26.3145529],
      [-48.828375, -26.3130097]
    ],
    [
      [-48.8290509, -26.3163231],
      [-48.829065, -26.316365],
      [-48.8291084, -26.316488],
      [-48.8291317, -26.3165249],
      [-48.8291879, -26.3166266],
      [-48.8292454, -26.3166623],
      [-48.8293164, -26.3166777],
      [-48.8294044, -26.3166954]
    ],
    [
      [-48.8584659, -26.3130375],
      [-48.8581703, -26.3128188],
      [-48.8578469, -26.3125763],
      [-48.8577671, -26.3125171],
      [-48.8576805, -26.3124575],
      [-48.8576288, -26.3124242],
      [-48.8575729, -26.3123906],
      [-48.8575094, -26.3123572],
      [-48.8574666, -26.3123365],
      [-48.8569137, -26.3120723],
      [-48.8566988, -26.311962],
      [-48.8566417, -26.3119268],
      [-48.8565908, -26.3118944],
      [-48.856541, -26.3118545]
    ],
    [
      [-48.8520815, -26.3224736],
      [-48.8516452, -26.3220898],
      [-48.8516045, -26.3220543],
      [-48.8514867, -26.3219514]
    ],
    [
      [-49.0009231, -26.1417367],
      [-49.001084, -26.1421834]
    ],
    [
      [-49.0009231, -26.1417367],
      [-49.0003511, -26.1407459]
    ],
    [
      [-49.001084, -26.1421834],
      [-49.0010827, -26.1422291],
      [-49.0010621, -26.1422877],
      [-49.0010069, -26.1423631],
      [-49.0009583, -26.1424007],
      [-49.0009499, -26.1424627],
      [-49.0010179, -26.1425396],
      [-49.001534, -26.1430749]
    ],
    [
      [-48.8546788, -26.3107658],
      [-48.8547225, -26.3107301],
      [-48.8547598, -26.3106961],
      [-48.8548076, -26.3106513]
    ],
    [
      [-48.8461155, -26.3058332],
      [-48.8460885, -26.3058285],
      [-48.8459041, -26.3057968],
      [-48.8458976, -26.3057957]
    ],
    [
      [-48.845953, -26.3057774],
      [-48.8459039, -26.3057689],
      [-48.8458976, -26.3057957]
    ],
    [
      [-48.9023342, -26.2873981],
      [-48.9024321, -26.2873896],
      [-48.9025274, -26.2873784]
    ],
    [
      [-48.8225419, -26.3831088],
      [-48.822412, -26.3831073],
      [-48.8223525, -26.3831067],
      [-48.8214733, -26.3830969],
      [-48.8203862, -26.3830847]
    ],
    [
      [-48.817102, -26.3895351],
      [-48.8169878, -26.3897815],
      [-48.8169502, -26.3898754],
      [-48.8169079, -26.3899946],
      [-48.8168599, -26.3901509],
      [-48.8166702, -26.3908978],
      [-48.8166293, -26.3910758],
      [-48.8165938, -26.3912157],
      [-48.8165511, -26.391349],
      [-48.8165063, -26.3914552],
      [-48.8164612, -26.3915417],
      [-48.8163957, -26.39164],
      [-48.8163243, -26.3917483],
      [-48.8162692, -26.3918219]
    ],
    [
      [-48.8186205, -26.2179301],
      [-48.8192115, -26.2173132],
      [-48.8196796, -26.2168247],
      [-48.819847, -26.2166499],
      [-48.8201734, -26.2163092],
      [-48.8206114, -26.2158521],
      [-48.8210782, -26.2153648]
    ],
    [
      [-48.8178322, -26.2342864],
      [-48.8179931, -26.2336669],
      [-48.8181728, -26.2329547],
      [-48.8183257, -26.2322979],
      [-48.8183498, -26.2321198],
      [-48.8183525, -26.2319586],
      [-48.8183525, -26.2317565],
      [-48.8183364, -26.2315857],
      [-48.81826, -26.2309999],
      [-48.8182356, -26.2307925],
      [-48.8182323, -26.2306472],
      [-48.8182418, -26.2305108],
      [-48.8182621, -26.2303746],
      [-48.8184376, -26.2292657],
      [-48.8185699, -26.2283413],
      [-48.8186133, -26.2280794],
      [-48.818667, -26.2278109],
      [-48.8187125, -26.2276513]
    ],
    [
      [-48.8216187, -26.2666967],
      [-48.8214327, -26.2665426],
      [-48.8213773, -26.2664951],
      [-48.821284, -26.2664105],
      [-48.8210788, -26.2662056],
      [-48.8208454, -26.2659588],
      [-48.820414, -26.2654892],
      [-48.8202277, -26.2652723],
      [-48.8199778, -26.2649719],
      [-48.8197904, -26.2647393],
      [-48.8196231, -26.26452],
      [-48.8194947, -26.2643493],
      [-48.8191502, -26.2638704],
      [-48.8190834, -26.2637761],
      [-48.8190554, -26.2637368]
    ],
    [
      [-48.8256965, -26.2702423],
      [-48.825735, -26.2702759],
      [-48.8260591, -26.2705583]
    ],
    [
      [-48.8221911, -26.2674359],
      [-48.8221272, -26.2672839],
      [-48.8220705, -26.2671727],
      [-48.8220301, -26.2671034],
      [-48.82198, -26.2670364],
      [-48.8219238, -26.2669766],
      [-48.8216187, -26.2666967]
    ],
    [
      [-48.8223926, -26.2673625],
      [-48.8225018, -26.2674576],
      [-48.8227826, -26.2677024],
      [-48.8230126, -26.2679029],
      [-48.8235036, -26.2683309],
      [-48.8242306, -26.2689646],
      [-48.8247975, -26.2694587],
      [-48.824923, -26.2695681],
      [-48.8250061, -26.2696405],
      [-48.8253408, -26.2699322],
      [-48.8256549, -26.2702061],
      [-48.8256965, -26.2702423]
    ],
    [
      [-48.8136407, -26.2702608],
      [-48.8137205, -26.2702592],
      [-48.8138384, -26.2702654],
      [-48.8139459, -26.2702787],
      [-48.8140853, -26.2703004],
      [-48.8146122, -26.2703839],
      [-48.8149131, -26.2704291],
      [-48.8150979, -26.2704537],
      [-48.8152406, -26.2704686],
      [-48.8154989, -26.2704868],
      [-48.8157276, -26.2704936],
      [-48.8159588, -26.2704966],
      [-48.8164321, -26.2704961],
      [-48.8171135, -26.2705053],
      [-48.8172878, -26.2705107],
      [-48.8180527, -26.2705286],
      [-48.8181914, -26.2705347],
      [-48.8183166, -26.2705464],
      [-48.8184352, -26.2705644]
    ],
    [
      [-48.8317388, -26.2738984],
      [-48.8319572, -26.2739913],
      [-48.8320982, -26.2740531],
      [-48.8322363, -26.2741111],
      [-48.832369, -26.2741864],
      [-48.8324953, -26.2742613],
      [-48.8325936, -26.2743233],
      [-48.8326731, -26.27438],
      [-48.8327776, -26.2744583],
      [-48.8328577, -26.2745245],
      [-48.8329442, -26.2746058],
      [-48.8331475, -26.2748275],
      [-48.8335429, -26.2752678]
    ],
    [
      [-48.8226312, -26.2715247],
      [-48.8228865, -26.2715844],
      [-48.8229629, -26.2715974],
      [-48.8230482, -26.2716045],
      [-48.8231565, -26.2716098],
      [-48.8231748, -26.2716093],
      [-48.8232475, -26.2716071],
      [-48.8233362, -26.2715973],
      [-48.8234134, -26.2715793]
    ],
    [
      [-48.8221911, -26.2674359],
      [-48.8222012, -26.267387],
      [-48.8222193, -26.2673619],
      [-48.822253, -26.267347],
      [-48.82228, -26.2673438],
      [-48.8223189, -26.2673466],
      [-48.8223926, -26.2673625]
    ],
    [
      [-48.8190804, -26.2603314],
      [-48.8190884, -26.2603119],
      [-48.8191493, -26.260163],
      [-48.8192174, -26.2600149],
      [-48.8192946, -26.2598593],
      [-48.8193675, -26.2597149],
      [-48.8194059, -26.2596387]
    ],
    [
      [-48.8427034, -26.3638345],
      [-48.8424143, -26.3638484]
    ],
    [
      [-48.838335, -26.367876],
      [-48.8390231, -26.3673894]
    ],
    [
      [-48.8725157, -26.3186236],
      [-48.8732776, -26.3185984],
      [-48.8747503, -26.3185497],
      [-48.8749376, -26.3185435],
      [-48.8755614, -26.3185229]
    ],
    [
      [-48.8320323, -26.2387157],
      [-48.8307325, -26.23691],
      [-48.8303472, -26.2363746]
    ],
    [
      [-48.8113895, -26.2828192],
      [-48.8113765, -26.2829614],
      [-48.8107147, -26.2837226],
      [-48.8105732, -26.2840595],
      [-48.8105641, -26.2844073],
      [-48.8106067, -26.2848411],
      [-48.8105002, -26.2852039],
      [-48.8105139, -26.2855245],
      [-48.810625, -26.286036],
      [-48.8106097, -26.2860647],
      [-48.8105959, -26.2860667],
      [-48.810469, -26.2860935],
      [-48.8103027, -26.2861244]
    ],
    [
      [-48.8122995, -26.2902429],
      [-48.8122005, -26.290247],
      [-48.8115432, -26.2895391],
      [-48.8113728, -26.2893004],
      [-48.8111766, -26.2889512],
      [-48.8110692, -26.2887955],
      [-48.810963, -26.2884594],
      [-48.8109385, -26.2883605],
      [-48.8109657, -26.288284],
      [-48.8104104, -26.2862925],
      [-48.8103161, -26.2861943],
      [-48.8103027, -26.2861244],
      [-48.8102857, -26.2860431],
      [-48.8102553, -26.2858764],
      [-48.809919, -26.2850825],
      [-48.8098034, -26.2848575],
      [-48.8097532, -26.2847838],
      [-48.8095935, -26.284661],
      [-48.8094717, -26.2846297],
      [-48.8093622, -26.284601],
      [-48.8092403, -26.2844975]
    ],
    [
      [-48.8097532, -26.2847838],
      [-48.8098184, -26.2846969],
      [-48.8099411, -26.2845524],
      [-48.8099814, -26.2845028],
      [-48.8100453, -26.2843882],
      [-48.8104496, -26.2834898],
      [-48.8107162, -26.2829218],
      [-48.8108606, -26.2826253]
    ],
    [
      [-48.8458976, -26.3057957],
      [-48.8458073, -26.3058396]
    ],
    [
      [-48.8629437, -26.3068341],
      [-48.8631856, -26.3096914],
      [-48.86333, -26.3113976],
      [-48.863346, -26.3116149],
      [-48.8633557, -26.3117562],
      [-48.8633616, -26.3119107],
      [-48.8633613, -26.3120414],
      [-48.8633558, -26.3121687],
      [-48.8633419, -26.3122971],
      [-48.8633239, -26.3123866],
      [-48.8633015, -26.3124786],
      [-48.86327, -26.3125626],
      [-48.8632298, -26.3126479],
      [-48.8631672, -26.3127461],
      [-48.8630881, -26.3128414],
      [-48.8629924, -26.3129309]
    ],
    [
      [-48.8455355, -26.3034375],
      [-48.8455062, -26.3034385],
      [-48.8451836, -26.3034499],
      [-48.8451375, -26.3034515],
      [-48.84491, -26.3034595],
      [-48.8445951, -26.3034705],
      [-48.8444576, -26.3034754],
      [-48.8441443, -26.3034864],
      [-48.8438228, -26.3034978],
      [-48.8437472, -26.3035]
    ],
    [
      [-48.8173463, -26.3434346],
      [-48.8173783, -26.3435426],
      [-48.8173991, -26.3436629],
      [-48.8174072, -26.343781],
      [-48.8174051, -26.3443999],
      [-48.8174081, -26.3445329],
      [-48.8174178, -26.3446841],
      [-48.8174323, -26.3448552],
      [-48.8174616, -26.3451652],
      [-48.8175314, -26.3458004],
      [-48.8175534, -26.3459327],
      [-48.8175792, -26.346033],
      [-48.8176153, -26.3461322],
      [-48.8176664, -26.3462263],
      [-48.8177046, -26.3462926],
      [-48.8177787, -26.3464009],
      [-48.8178336, -26.3464714],
      [-48.8178953, -26.3465434],
      [-48.8179683, -26.3466087],
      [-48.8181464, -26.346767],
      [-48.8182176, -26.3468384],
      [-48.8183059, -26.3469498],
      [-48.818377, -26.3470698],
      [-48.8184215, -26.3471749],
      [-48.8184458, -26.3472604],
      [-48.8184597, -26.3473368],
      [-48.8184682, -26.3474287],
      [-48.8184644, -26.3475225],
      [-48.8184513, -26.3476191],
      [-48.8184373, -26.3477279],
      [-48.8183507, -26.3481799],
      [-48.8183312, -26.3483128],
      [-48.8183202, -26.3483856],
      [-48.8183123, -26.3484374],
      [-48.8183086, -26.3485813],
      [-48.818312, -26.3487021],
      [-48.8183276, -26.348811],
      [-48.8183484, -26.3489039],
      [-48.8186606, -26.3499522],
      [-48.8187436, -26.3502308],
      [-48.8188544, -26.350603],
      [-48.8189, -26.3507302]
    ],
    [
      [-48.8491175, -26.3024924],
      [-48.8488849, -26.3022919],
      [-48.8482402, -26.3017364],
      [-48.8481848, -26.3017054],
      [-48.8481321, -26.3016935],
      [-48.8480804, -26.3017048],
      [-48.8480241, -26.301737]
    ],
    [
      [-48.8201081, -26.3553512],
      [-48.8200944, -26.3555045],
      [-48.8200783, -26.3556137],
      [-48.8200563, -26.355685],
      [-48.8200099, -26.3557894],
      [-48.8199015, -26.3560153],
      [-48.819873, -26.356105],
      [-48.8198636, -26.3561683],
      [-48.819865, -26.3562591],
      [-48.819878, -26.3563407],
      [-48.8199492, -26.3566324],
      [-48.8199712, -26.3567409],
      [-48.8199782, -26.3568189],
      [-48.8199718, -26.3569218],
      [-48.8199554, -26.3569905],
      [-48.8199262, -26.3570596],
      [-48.8199048, -26.3570967],
      [-48.8198661, -26.3571566],
      [-48.8198257, -26.3572099],
      [-48.8197782, -26.3572588],
      [-48.8197095, -26.3573174],
      [-48.8192611, -26.3576403],
      [-48.8184664, -26.3582053],
      [-48.8183799, -26.3582682],
      [-48.8183065, -26.3583278],
      [-48.8182512, -26.358387],
      [-48.8182141, -26.3584396],
      [-48.8181736, -26.3585232],
      [-48.8181538, -26.3586136],
      [-48.8181469, -26.3587045],
      [-48.8182213, -26.3595392]
    ],
    [
      [-48.8202779, -26.3523657],
      [-48.8203141, -26.3524927],
      [-48.8203255, -26.352603],
      [-48.8203284, -26.3526954],
      [-48.820323, -26.352806],
      [-48.820224, -26.3537884],
      [-48.8202018, -26.3540953],
      [-48.8201081, -26.3553512]
    ],
    [
      [-48.7944308, -26.3432703],
      [-48.7933266, -26.344474],
      [-48.7929776, -26.3448545],
      [-48.7928072, -26.3450403],
      [-48.7926236, -26.3452404],
      [-48.7923698, -26.3455172],
      [-48.7921447, -26.3457625]
    ],
    [
      [-48.821576, -26.3409926],
      [-48.8208905, -26.340895],
      [-48.820703, -26.3408703],
      [-48.8205348, -26.3408503],
      [-48.8203722, -26.3408383],
      [-48.8202524, -26.3408323],
      [-48.8200379, -26.3408322],
      [-48.8197366, -26.340832],
      [-48.8196572, -26.3408324],
      [-48.8193703, -26.3408331],
      [-48.8190187, -26.3408325],
      [-48.8189597, -26.340831],
      [-48.8187915, -26.3408267],
      [-48.8185988, -26.3408194],
      [-48.8184826, -26.3408101],
      [-48.8183075, -26.3407816],
      [-48.8174272, -26.3406],
      [-48.8171073, -26.340543],
      [-48.8169472, -26.3405233],
      [-48.816821, -26.3405135],
      [-48.8166565, -26.3405077],
      [-48.8164862, -26.3405074]
    ],
    [
      [-48.844226, -26.3383653],
      [-48.8434276, -26.3387398],
      [-48.8432754, -26.3388042],
      [-48.8431509, -26.3388438],
      [-48.8429116, -26.3389126],
      [-48.8417612, -26.3392518],
      [-48.8414931, -26.3393309]
    ],
    [
      [-48.8182213, -26.3595392],
      [-48.8182754, -26.360146],
      [-48.818326, -26.3607128],
      [-48.8184209, -26.3617766]
    ],
    [
      [-48.8427673, -26.3420929],
      [-48.8421103, -26.3414137],
      [-48.8418618, -26.3411568],
      [-48.841815, -26.3411064],
      [-48.8417654, -26.3410509],
      [-48.841712, -26.3409802],
      [-48.8416581, -26.3408997],
      [-48.8416255, -26.3408392],
      [-48.841578, -26.3407377],
      [-48.8415275, -26.3406098],
      [-48.8415023, -26.3405186],
      [-48.8414842, -26.3404306],
      [-48.8414702, -26.3403257],
      [-48.8414646, -26.3402426],
      [-48.8414634, -26.3401411],
      [-48.8414622, -26.3400551],
      [-48.8414664, -26.3399267],
      [-48.8414754, -26.3397148]
    ],
    [
      [-48.8387336, -26.3546679],
      [-48.8387032, -26.3544294],
      [-48.8386789, -26.3541978],
      [-48.8386639, -26.3539854],
      [-48.8386049, -26.3529807],
      [-48.8385834, -26.3527596],
      [-48.8385727, -26.3525241],
      [-48.8385952, -26.3522444],
      [-48.8386752, -26.3519677],
      [-48.8387825, -26.3517071],
      [-48.8389113, -26.3514524],
      [-48.8391316, -26.3511398],
      [-48.8400267, -26.3500548],
      [-48.8410286, -26.3488403],
      [-48.84117, -26.3486645],
      [-48.8416886, -26.3480386]
    ],
    [
      [-48.8194059, -26.2596387],
      [-48.8196312, -26.2591847],
      [-48.8197671, -26.2588977]
    ],
    [
      [-48.8089305, -26.2844529],
      [-48.8080542, -26.2843283],
      [-48.8072455, -26.2842128],
      [-48.8064349, -26.2840975],
      [-48.8060206, -26.284038],
      [-48.8052855, -26.2839348],
      [-48.8044627, -26.2838178],
      [-48.8042745, -26.283791],
      [-48.8036217, -26.2836982],
      [-48.8027951, -26.2835807],
      [-48.8019547, -26.2834613],
      [-48.801122, -26.2833429],
      [-48.8009462, -26.2833179],
      [-48.8007574, -26.2832911],
      [-48.8003166, -26.2832284],
      [-48.7994768, -26.283109],
      [-48.7993481, -26.2830907],
      [-48.7988486, -26.2830197],
      [-48.798683, -26.2829962]
    ],
    [
      [-48.8519508, -26.2597067],
      [-48.8515972, -26.2596393]
    ],
    [
      [-48.8355314, -26.2684724],
      [-48.8358694, -26.2681116],
      [-48.8359959, -26.2679845],
      [-48.8361108, -26.2678877],
      [-48.8362294, -26.2677988],
      [-48.836336, -26.267727],
      [-48.8364247, -26.2676735],
      [-48.8365036, -26.2676279],
      [-48.8366166, -26.2675693],
      [-48.8367497, -26.2675072],
      [-48.836945, -26.2674286],
      [-48.8371466, -26.2673602],
      [-48.8373232, -26.2673179],
      [-48.8375556, -26.2672754],
      [-48.8381548, -26.2671983],
      [-48.8390206, -26.267087]
    ],
    [
      [-48.8401118, -26.2827244],
      [-48.8401811, -26.282769],
      [-48.8402526, -26.2828171],
      [-48.8405754, -26.2830482],
      [-48.8406421, -26.2830917],
      [-48.8406979, -26.2831174],
      [-48.8407444, -26.2831319],
      [-48.8408028, -26.2831413],
      [-48.8408679, -26.2831428],
      [-48.8409523, -26.2831347]
    ],
    [
      [-48.8197671, -26.2588977],
      [-48.8198763, -26.2586744]
    ],
    [
      [-48.8416886, -26.3480386],
      [-48.8418437, -26.3478437],
      [-48.8419184, -26.3477397],
      [-48.8419863, -26.3476437],
      [-48.8420503, -26.3475406],
      [-48.8421056, -26.3474348],
      [-48.8421473, -26.3473356],
      [-48.8421704, -26.3472625],
      [-48.8421917, -26.3471623],
      [-48.8422022, -26.3470522],
      [-48.842233, -26.3466272],
      [-48.8422761, -26.3459311]
    ],
    [
      [-48.8416805, -26.3356949],
      [-48.8416865, -26.3355747],
      [-48.8417015, -26.3352715],
      [-48.8417449, -26.3343977],
      [-48.8417811, -26.3336695],
      [-48.8417943, -26.3334038],
      [-48.8418332, -26.3326207],
      [-48.8418355, -26.3325739]
    ],
    [
      [-48.8162217, -26.2946652],
      [-48.8158007, -26.2944345],
      [-48.8157016, -26.2943727],
      [-48.815582, -26.2942854],
      [-48.8154776, -26.2941968],
      [-48.8153826, -26.2941054],
      [-48.8153036, -26.2940068],
      [-48.814773, -26.2932519],
      [-48.814401, -26.2927225]
    ],
    [
      [-48.861871, -26.2938996],
      [-48.8632336, -26.2938083],
      [-48.8639013, -26.2937635],
      [-48.864473, -26.2937253],
      [-48.8646355, -26.2937144]
    ],
    [
      [-48.8540439, -26.2944236],
      [-48.855437, -26.2943304],
      [-48.8577048, -26.2941785],
      [-48.858381, -26.2941332],
      [-48.8591022, -26.2940849],
      [-48.8595847, -26.2940526],
      [-48.8601295, -26.2940161]
    ],
    [
      [-48.8622417, -26.2969013],
      [-48.8621275, -26.2969374],
      [-48.8620484, -26.2969742],
      [-48.8619636, -26.2970272],
      [-48.861888, -26.2970806],
      [-48.8617912, -26.2971583],
      [-48.8615817, -26.2973478],
      [-48.8615062, -26.2974013],
      [-48.8614316, -26.2974461],
      [-48.8613709, -26.297477],
      [-48.8612887, -26.2975136],
      [-48.8609059, -26.2976618],
      [-48.8604324, -26.2978407]
    ],
    [
      [-48.8502181, -26.2946798],
      [-48.8503215, -26.2946729],
      [-48.852543, -26.2945241],
      [-48.8526974, -26.2945138],
      [-48.8538909, -26.2944339],
      [-48.8540439, -26.2944236]
    ],
    [
      [-48.9043473, -26.3368631],
      [-48.9042666, -26.3360613],
      [-48.9041707, -26.335217],
      [-48.904096, -26.3345867]
    ],
    [
      [-48.8164862, -26.3405074],
      [-48.8163449, -26.3405241],
      [-48.8159184, -26.3405911],
      [-48.8158506, -26.3406026]
    ],
    [
      [-48.8088928, -26.3396286],
      [-48.8087161, -26.3396316],
      [-48.8079928, -26.3396486],
      [-48.8076611, -26.3396524],
      [-48.8075423, -26.3396414],
      [-48.8074285, -26.3396215],
      [-48.8073416, -26.3395982],
      [-48.8072514, -26.3395644],
      [-48.8071459, -26.3395144],
      [-48.8069612, -26.339403],
      [-48.8067941, -26.3392893],
      [-48.8066223, -26.3391748],
      [-48.8064718, -26.3390811],
      [-48.8064046, -26.3390403],
      [-48.8060515, -26.3388259],
      [-48.8058616, -26.3387155],
      [-48.8056389, -26.338593],
      [-48.8054813, -26.3385104],
      [-48.8053402, -26.3384441]
    ],
    [
      [-48.8681413, -26.2934797],
      [-48.8681441, -26.2935405],
      [-48.8682184, -26.2951901]
    ],
    [
      [-48.8192488, -26.2799334],
      [-48.8186474, -26.2805739],
      [-48.8183003, -26.2809437],
      [-48.8181269, -26.2811284],
      [-48.8177042, -26.2815787]
    ],
    [
      [-48.8119536, -26.2821715],
      [-48.8123441, -26.2817232],
      [-48.812577, -26.2814558]
    ],
    [
      [-48.8103464, -26.2691753],
      [-48.8102844, -26.2690876],
      [-48.8099299, -26.2685864]
    ],
    [
      [-48.850061, -26.3331641],
      [-48.8500211, -26.3331361],
      [-48.8499911, -26.3331136],
      [-48.8499906, -26.3329622],
      [-48.8496687, -26.3329601],
      [-48.8496687, -26.3329706]
    ],
    [
      [-48.8033381, -26.3178582],
      [-48.8030788, -26.3174477]
    ],
    [
      [-48.8018704, -26.3155349],
      [-48.8017401, -26.3153301],
      [-48.8013796, -26.3147636]
    ],
    [
      [-48.8187125, -26.2276513],
      [-48.8187349, -26.2275907],
      [-48.8201076, -26.224881],
      [-48.8204378, -26.2242253]
    ],
    [
      [-48.8214215, -26.2482652],
      [-48.8214322, -26.2478082],
      [-48.8214233, -26.2476598],
      [-48.8214107, -26.2475291],
      [-48.8213807, -26.2473868],
      [-48.8213499, -26.2472879],
      [-48.821211, -26.2468974]
    ],
    [
      [-48.8181245, -26.3195978],
      [-48.8180397, -26.3196238],
      [-48.816065, -26.3202295]
    ],
    [
      [-48.8091625, -26.3223638],
      [-48.8093279, -26.322296]
    ],
    [
      [-48.8543095, -26.3065267],
      [-48.8544685, -26.3065669],
      [-48.8545454, -26.3065955],
      [-48.8546177, -26.30663],
      [-48.8546883, -26.3066723],
      [-48.8547616, -26.3067189],
      [-48.8548402, -26.3067826],
      [-48.8549409, -26.3068834],
      [-48.8550077, -26.306962],
      [-48.8550657, -26.3070374],
      [-48.8550965, -26.3070945],
      [-48.8551205, -26.3071485],
      [-48.8551352, -26.3072135]
    ],
    [
      [-48.8530867, -26.2989642],
      [-48.853033, -26.2990026],
      [-48.8529073, -26.2990958],
      [-48.8523619, -26.2994832],
      [-48.8521988, -26.2995845],
      [-48.85211, -26.2996346],
      [-48.8519844, -26.299692],
      [-48.851775, -26.2997721],
      [-48.8516799, -26.299812],
      [-48.8516058, -26.2998474],
      [-48.8515313, -26.2998886],
      [-48.8507876, -26.3003766],
      [-48.8506834, -26.300431]
    ],
    [
      [-48.8359415, -26.30702],
      [-48.8369822, -26.3065574],
      [-48.8371411, -26.3064757],
      [-48.8372444, -26.3064113],
      [-48.8373452, -26.3063253],
      [-48.837424, -26.3062476],
      [-48.8374967, -26.3061671],
      [-48.8375715, -26.3060522],
      [-48.8376317, -26.3059338],
      [-48.8376871, -26.3058065],
      [-48.8377628, -26.3056128],
      [-48.8378453, -26.3053916],
      [-48.8379137, -26.3052356],
      [-48.8379971, -26.3050931],
      [-48.8380853, -26.3049576],
      [-48.8381495, -26.3048657],
      [-48.8382265, -26.3047601],
      [-48.8383153, -26.3046494],
      [-48.8385272, -26.3044039]
    ],
    [
      [-48.8499455, -26.30841],
      [-48.8515592, -26.3068843],
      [-48.851637, -26.3068107]
    ],
    [
      [-48.8362652, -26.3257037],
      [-48.8354922, -26.3251939],
      [-48.8353963, -26.3251466],
      [-48.8353388, -26.3251234],
      [-48.8352626, -26.3251031],
      [-48.8351971, -26.3250951],
      [-48.8351265, -26.325091],
      [-48.835024, -26.3250977],
      [-48.834928, -26.3251104],
      [-48.8348269, -26.3251379],
      [-48.8347392, -26.3251711],
      [-48.8344034, -26.3253081],
      [-48.8341864, -26.325397],
      [-48.8341259, -26.3254178],
      [-48.8340584, -26.3254374],
      [-48.8339592, -26.325461],
      [-48.8338466, -26.3254833],
      [-48.8337161, -26.325504],
      [-48.8335754, -26.325524],
      [-48.8315589, -26.3258107],
      [-48.8314533, -26.3258199]
    ],
    [
      [-48.8547323, -26.3105783],
      [-48.8536749, -26.3101481],
      [-48.8535712, -26.3101063],
      [-48.8534487, -26.3100561],
      [-48.8528276, -26.3098033],
      [-48.8526653, -26.3097373],
      [-48.8525185, -26.3096776],
      [-48.8517974, -26.3093842],
      [-48.8513443, -26.3091998]
    ],
    [
      [-48.8545962, -26.3108305],
      [-48.8546788, -26.3107658]
    ],
    [
      [-48.8308838, -26.3259222],
      [-48.8308412, -26.3259257],
      [-48.8307991, -26.3259234],
      [-48.8307549, -26.3259183],
      [-48.8307133, -26.3259084],
      [-48.8306333, -26.3258726]
    ],
    [
      [-48.8033381, -26.3178582],
      [-48.803279, -26.3177391],
      [-48.8032453, -26.3176417],
      [-48.8032236, -26.3175429],
      [-48.8032099, -26.3174404],
      [-48.8032018, -26.3173253],
      [-48.8032073, -26.31722],
      [-48.803224, -26.317123],
      [-48.8032438, -26.3170242],
      [-48.8032691, -26.3169364],
      [-48.8033087, -26.3168455],
      [-48.8033647, -26.3167442],
      [-48.803449, -26.3166234],
      [-48.8035232, -26.3165214],
      [-48.8043668, -26.3153274],
      [-48.8046471, -26.3149307],
      [-48.8049215, -26.3145422]
    ],
    [
      [-48.8170029, -26.3332665],
      [-48.8169994, -26.3324189],
      [-48.8170077, -26.3322359],
      [-48.8170124, -26.3321325],
      [-48.8170214, -26.3320328],
      [-48.8170392, -26.3319467],
      [-48.8170763, -26.3318424],
      [-48.8171447, -26.3316879],
      [-48.8173704, -26.3311438],
      [-48.8174037, -26.3310429],
      [-48.8174288, -26.3309509],
      [-48.8174529, -26.3308607],
      [-48.8174749, -26.3307408],
      [-48.8174913, -26.3306431],
      [-48.8175047, -26.3305206],
      [-48.8175128, -26.3303956],
      [-48.817515, -26.3301092],
      [-48.8175202, -26.3294443],
      [-48.8175251, -26.3287962],
      [-48.8175303, -26.328123],
      [-48.8175354, -26.3274634]
    ],
    [
      [-48.8293002, -26.3248816],
      [-48.8292261, -26.3248136],
      [-48.8291575, -26.3247382],
      [-48.8290715, -26.3246358],
      [-48.8290075, -26.3245507],
      [-48.8289523, -26.3244719],
      [-48.8288934, -26.3243726],
      [-48.8288454, -26.3242869],
      [-48.8285133, -26.323703],
      [-48.8282942, -26.3233066],
      [-48.828249, -26.3232298],
      [-48.8281865, -26.3231219],
      [-48.8281353, -26.3230401],
      [-48.8277474, -26.3225109],
      [-48.8276682, -26.3224101],
      [-48.8275742, -26.3223036],
      [-48.8275086, -26.3222363],
      [-48.8274301, -26.3221691],
      [-48.8272564, -26.322042],
      [-48.8271923, -26.3219942],
      [-48.8271315, -26.3219432],
      [-48.8270774, -26.3218838],
      [-48.8270356, -26.321829],
      [-48.8269859, -26.3217515],
      [-48.8269565, -26.3216964],
      [-48.8268317, -26.3213995],
      [-48.8267928, -26.3213119],
      [-48.8267557, -26.3212462]
    ],
    [
      [-48.8301326, -26.3255068],
      [-48.8300694, -26.3254603],
      [-48.8295391, -26.3250698],
      [-48.8294432, -26.3249992]
    ],
    [
      [-48.8427069, -26.3145954],
      [-48.8427115, -26.3144968],
      [-48.8427819, -26.3129754],
      [-48.8427859, -26.3128893],
      [-48.8428137, -26.3122876],
      [-48.8428211, -26.3121287],
      [-48.8428253, -26.312037],
      [-48.8428586, -26.3113171],
      [-48.842864, -26.3112005]
    ],
    [
      [-48.8317433, -26.3343105],
      [-48.8316742, -26.3348942],
      [-48.8316327, -26.3351766],
      [-48.8316214, -26.3352571],
      [-48.8316195, -26.3353544],
      [-48.8316287, -26.335421],
      [-48.8316424, -26.3355042],
      [-48.8316535, -26.3355629],
      [-48.8316794, -26.3357078],
      [-48.8316927, -26.3358108],
      [-48.8317118, -26.33597],
      [-48.8317213, -26.3361268],
      [-48.8317236, -26.3362516],
      [-48.8317243, -26.3363693],
      [-48.8317076, -26.3365736]
    ],
    [
      [-48.8060519, -26.3229151],
      [-48.8061366, -26.3233779],
      [-48.8062102, -26.3237803],
      [-48.8062207, -26.3238397],
      [-48.8062377, -26.3239022],
      [-48.8062686, -26.3240046],
      [-48.8063239, -26.3241211],
      [-48.8063773, -26.3242071],
      [-48.8064353, -26.3242811],
      [-48.8065047, -26.3243593],
      [-48.8066028, -26.3244489],
      [-48.8066932, -26.3245159],
      [-48.8067845, -26.3245689],
      [-48.8069366, -26.3246389],
      [-48.8073727, -26.3248247],
      [-48.8078093, -26.3250107],
      [-48.8079666, -26.3250757]
    ],
    [
      [-48.8068047, -26.3247295],
      [-48.8066071, -26.3246222],
      [-48.8065074, -26.3245543],
      [-48.8064334, -26.3244935],
      [-48.8063548, -26.3244187],
      [-48.8062788, -26.324332],
      [-48.8062177, -26.3242486],
      [-48.8061616, -26.324144],
      [-48.8061112, -26.3240054],
      [-48.806074, -26.3238617],
      [-48.8059891, -26.3234006],
      [-48.8059039, -26.3229374],
      [-48.8058206, -26.3224848],
      [-48.8057342, -26.3220154],
      [-48.8056665, -26.321714],
      [-48.8056205, -26.3215391],
      [-48.8055866, -26.3214445],
      [-48.8055511, -26.3213678],
      [-48.805501, -26.3212819],
      [-48.8046307, -26.3199043],
      [-48.8043687, -26.3194895],
      [-48.8041104, -26.3190807],
      [-48.8038544, -26.3186754],
      [-48.8035974, -26.3182687],
      [-48.8033923, -26.317944],
      [-48.8033381, -26.3178582]
    ],
    [
      [-48.8356873, -26.3073899],
      [-48.8355645, -26.3081983],
      [-48.835549, -26.3083068],
      [-48.8355315, -26.3083924],
      [-48.8355095, -26.3084761],
      [-48.8354789, -26.3085661],
      [-48.8354137, -26.308711],
      [-48.8353383, -26.3088516],
      [-48.8352399, -26.3090037],
      [-48.8351405, -26.3091281],
      [-48.8350521, -26.309234],
      [-48.834964, -26.3093323],
      [-48.8348302, -26.3094648],
      [-48.8347133, -26.3095621],
      [-48.834567, -26.3096702],
      [-48.8334673, -26.3104261],
      [-48.8331572, -26.3106346],
      [-48.8325684, -26.3110443],
      [-48.8324994, -26.3110909],
      [-48.8324122, -26.3111396],
      [-48.8323588, -26.3111638],
      [-48.8322573, -26.3111986],
      [-48.8321777, -26.3112189],
      [-48.8320937, -26.3112299],
      [-48.8319897, -26.3112299],
      [-48.8318756, -26.3112136],
      [-48.8317753, -26.3111904]
    ],
    [
      [-48.8318849, -26.3604621],
      [-48.8317521, -26.3604665]
    ],
    [
      [-48.813417, -26.2909341],
      [-48.8135649, -26.2910708],
      [-48.8139129, -26.2913923],
      [-48.8139639, -26.2914395],
      [-48.8140695, -26.2915371],
      [-48.8141831, -26.2916421],
      [-48.8154345, -26.2927985],
      [-48.8160245, -26.2933436],
      [-48.8164056, -26.2936958],
      [-48.8169901, -26.2942359],
      [-48.8172664, -26.2944913],
      [-48.8174805, -26.2946891],
      [-48.8178098, -26.2949935],
      [-48.8178744, -26.2950531],
      [-48.8183466, -26.2954895],
      [-48.8188466, -26.2959515],
      [-48.8189456, -26.296043]
    ],
    [
      [-48.7837552, -26.2865194],
      [-48.7824718, -26.2871897]
    ],
    [
      [-48.788312, -26.2850242],
      [-48.7870918, -26.2850109],
      [-48.7869644, -26.285015],
      [-48.7868288, -26.2850278]
    ],
    [
      [-48.777191, -26.2899475],
      [-48.7770386, -26.2900271],
      [-48.7769353, -26.290081],
      [-48.7752873, -26.2909416],
      [-48.7751384, -26.2910194],
      [-48.7750162, -26.2910754]
    ],
    [
      [-48.7868288, -26.2850278],
      [-48.7866799, -26.2850569],
      [-48.7865614, -26.2850873],
      [-48.7864613, -26.2851228],
      [-48.7863582, -26.2851667],
      [-48.786236, -26.2852238]
    ],
    [
      [-48.7824718, -26.2871897],
      [-48.7805835, -26.2881758],
      [-48.7784653, -26.289282],
      [-48.7774246, -26.2898255],
      [-48.777191, -26.2899475]
    ],
    [
      [-48.8409674, -26.3056494],
      [-48.8409694, -26.3054899],
      [-48.8409764, -26.3053502],
      [-48.8409877, -26.3052105],
      [-48.8409947, -26.3050904],
      [-48.841002, -26.3046766],
      [-48.8410055, -26.3044548]
    ],
    [
      [-48.8184209, -26.3617766],
      [-48.8180912, -26.3617928],
      [-48.8179592, -26.3618038],
      [-48.8178099, -26.3618279],
      [-48.8176881, -26.361853],
      [-48.817565, -26.3618845],
      [-48.8175185, -26.3618975],
      [-48.8174466, -26.3619177],
      [-48.8173092, -26.3619597],
      [-48.8165025, -26.3622587],
      [-48.8163621, -26.3622899],
      [-48.8162782, -26.3622937],
      [-48.8161497, -26.3622785],
      [-48.8160101, -26.3622477],
      [-48.8147323, -26.361857],
      [-48.8145966, -26.3618182],
      [-48.814482, -26.3617964],
      [-48.81436, -26.3617897],
      [-48.814116, -26.3617981]
    ],
    [
      [-48.810432, -26.3620409],
      [-48.8098217, -26.3620812],
      [-48.8091236, -26.3621272]
    ],
    [
      [-48.8121015, -26.3619309],
      [-48.810526, -26.3620347],
      [-48.810432, -26.3620409]
    ],
    [
      [-48.8091236, -26.3621272],
      [-48.8085032, -26.3621681],
      [-48.8083711, -26.3621768],
      [-48.8079929, -26.3622017],
      [-48.8078518, -26.362211]
    ],
    [
      [-48.8189, -26.3507302],
      [-48.8189411, -26.3508176],
      [-48.8189951, -26.3509119],
      [-48.8190636, -26.351005],
      [-48.8191376, -26.3510895],
      [-48.8193301, -26.3512919],
      [-48.8197032, -26.3516841],
      [-48.8197449, -26.3517279],
      [-48.8201245, -26.3521293],
      [-48.8201999, -26.352223],
      [-48.8202469, -26.3522997],
      [-48.8202779, -26.3523657]
    ],
    [
      [-48.8053402, -26.3384441],
      [-48.8052179, -26.3383982],
      [-48.805057, -26.3383473],
      [-48.8049119, -26.3383131],
      [-48.8047489, -26.338285],
      [-48.8045687, -26.3382684],
      [-48.8043529, -26.33826],
      [-48.8042137, -26.3382693],
      [-48.8041201, -26.3382818],
      [-48.8040205, -26.3383059],
      [-48.8038532, -26.3383741],
      [-48.803668, -26.338474],
      [-48.8034711, -26.3386032],
      [-48.8033971, -26.3386417],
      [-48.8033058, -26.3386785],
      [-48.8030776, -26.3387555],
      [-48.8026761, -26.3388715],
      [-48.8024272, -26.3389369],
      [-48.8022831, -26.338971],
      [-48.8018671, -26.3390667],
      [-48.8015087, -26.3391449],
      [-48.8014485, -26.3391586],
      [-48.8013822, -26.3391732],
      [-48.8013359, -26.3391839],
      [-48.8010577, -26.3392436],
      [-48.8003791, -26.3393837],
      [-48.8000468, -26.3394581],
      [-48.7999164, -26.3394958],
      [-48.7997557, -26.3395532],
      [-48.7995814, -26.3396414]
    ],
    [
      [-48.8148028, -26.3404478],
      [-48.8146423, -26.3404106],
      [-48.8142005, -26.3403026],
      [-48.8137364, -26.3401769],
      [-48.8136206, -26.3401393]
    ],
    [
      [-48.8246427, -26.3394481],
      [-48.8242702, -26.3397079],
      [-48.8240841, -26.3398448],
      [-48.8240316, -26.3398873],
      [-48.823768, -26.3400905],
      [-48.8236721, -26.3401658],
      [-48.8235752, -26.34023],
      [-48.8234243, -26.340314],
      [-48.8231229, -26.3404636]
    ],
    [
      [-48.8308879, -26.334275],
      [-48.8308457, -26.3342698],
      [-48.8305145, -26.3342294],
      [-48.8302176, -26.3341967],
      [-48.8301087, -26.3341926],
      [-48.8300033, -26.3341996],
      [-48.8298823, -26.3342235],
      [-48.8297222, -26.3342744],
      [-48.829632, -26.334316],
      [-48.8295603, -26.334356],
      [-48.8294739, -26.3344195],
      [-48.8293973, -26.3344879],
      [-48.8293196, -26.3345663],
      [-48.8292095, -26.3347042],
      [-48.8291668, -26.3347884],
      [-48.8291326, -26.3348793],
      [-48.829115, -26.3349325],
      [-48.8290929, -26.3350362],
      [-48.8290673, -26.3352851],
      [-48.8290027, -26.3357535],
      [-48.8289829, -26.3358431],
      [-48.8289604, -26.3359352],
      [-48.8289339, -26.3360209],
      [-48.8288734, -26.3361287],
      [-48.8287997, -26.3362254],
      [-48.8286838, -26.3363363],
      [-48.828601, -26.3363991],
      [-48.828475, -26.33647],
      [-48.8282859, -26.3365607],
      [-48.8276341, -26.3368591],
      [-48.8268955, -26.3371819],
      [-48.8268016, -26.337229],
      [-48.8267278, -26.3372816],
      [-48.8266492, -26.3373499],
      [-48.8264064, -26.3376847],
      [-48.8263466, -26.3377669],
      [-48.8262517, -26.3378934],
      [-48.8259405, -26.3382829],
      [-48.8257304, -26.3385195]
    ],
    [
      [-48.8422761, -26.3459311],
      [-48.842315, -26.345449],
      [-48.8423247, -26.3453446],
      [-48.8423329, -26.3452802],
      [-48.8423462, -26.3452101],
      [-48.8423682, -26.3451377],
      [-48.8424111, -26.3450418],
      [-48.8424636, -26.3449476],
      [-48.8425295, -26.3448595],
      [-48.8426175, -26.3447546]
    ],
    [
      [-48.8426175, -26.3447546],
      [-48.8427921, -26.3445549],
      [-48.8428601, -26.344472],
      [-48.8429162, -26.3443996],
      [-48.842971, -26.3443169],
      [-48.8430207, -26.3442275],
      [-48.8430662, -26.34413],
      [-48.8431035, -26.3440173],
      [-48.8431225, -26.3439341],
      [-48.8431334, -26.3438541]
    ],
    [
      [-48.8625981, -26.3037113],
      [-48.8626437, -26.3042895],
      [-48.862695, -26.304973],
      [-48.8627175, -26.305257],
      [-48.8627622, -26.3057101],
      [-48.8627708, -26.3057876],
      [-48.8627821, -26.3058721]
    ],
    [
      [-48.8673738, -26.2853617],
      [-48.8672374, -26.2852426],
      [-48.8671516, -26.2851843],
      [-48.8670789, -26.2851461],
      [-48.8670221, -26.2851241],
      [-48.8668944, -26.2850904],
      [-48.8668057, -26.2850821],
      [-48.8665514, -26.2850872],
      [-48.866465, -26.2850814],
      [-48.8663708, -26.2850663],
      [-48.8662824, -26.2850369],
      [-48.8662095, -26.2850015],
      [-48.8661521, -26.2849635],
      [-48.8660575, -26.2848948],
      [-48.8656856, -26.2845975],
      [-48.8656176, -26.2845423],
      [-48.8655649, -26.2845104],
      [-48.8654959, -26.2844727],
      [-48.8654165, -26.2844478],
      [-48.8653248, -26.2844344],
      [-48.8652147, -26.2844297],
      [-48.8650612, -26.2844277],
      [-48.8648964, -26.2844256],
      [-48.8648219, -26.2844206],
      [-48.8647209, -26.2844039],
      [-48.8646413, -26.2843821],
      [-48.8645615, -26.2843539]
    ],
    [
      [-48.8675944, -26.2855722],
      [-48.8673738, -26.2853617]
    ],
    [
      [-48.8709863, -26.2852482],
      [-48.8703124, -26.2854292],
      [-48.8700826, -26.2854909],
      [-48.8697114, -26.2855896],
      [-48.869392, -26.2856723],
      [-48.8692534, -26.2857138],
      [-48.8691582, -26.2857481],
      [-48.8689934, -26.285817],
      [-48.8688588, -26.2858715],
      [-48.8685863, -26.2859819],
      [-48.8684975, -26.2860115],
      [-48.8684037, -26.2860287],
      [-48.8683316, -26.2860289],
      [-48.8682708, -26.2860229],
      [-48.8681552, -26.2859994],
      [-48.8680686, -26.2859664],
      [-48.8679914, -26.2859222],
      [-48.8679246, -26.2858684],
      [-48.8675944, -26.2855722]
    ],
    [
      [-48.8758633, -26.2847728],
      [-48.8755393, -26.2847862],
      [-48.8752152, -26.2847996],
      [-48.8750704, -26.2848058],
      [-48.8750007, -26.2848106]
    ],
    [
      [-48.8584034, -26.3171757],
      [-48.8590073, -26.3166175],
      [-48.8594383, -26.3162191],
      [-48.8613238, -26.3144764]
    ],
    [
      [-48.8601295, -26.2940161],
      [-48.8605223, -26.2939898],
      [-48.8607116, -26.2939771],
      [-48.8609044, -26.2939642],
      [-48.861871, -26.2938996]
    ],
    [
      [-48.8674624, -26.2857582],
      [-48.8675754, -26.2868072],
      [-48.867631, -26.2873236],
      [-48.8677323, -26.2882645],
      [-48.8677523, -26.2884501],
      [-48.8677659, -26.2885769]
    ],
    [
      [-48.8797212, -26.2659839],
      [-48.8801511, -26.26576],
      [-48.8808421, -26.2654045]
    ],
    [
      [-48.8599301, -26.2980105],
      [-48.8597217, -26.2980822],
      [-48.85957, -26.2981369],
      [-48.8594855, -26.2981723],
      [-48.8594041, -26.2982084],
      [-48.8593239, -26.2982497],
      [-48.8592112, -26.2983197],
      [-48.8587749, -26.2986133],
      [-48.8587037, -26.2986526],
      [-48.8586046, -26.2986945],
      [-48.858502, -26.2987237],
      [-48.8583874, -26.2987443],
      [-48.8582821, -26.2987526],
      [-48.8581802, -26.2987526],
      [-48.8580949, -26.298745],
      [-48.8580158, -26.2987368],
      [-48.8579213, -26.2987205],
      [-48.8571145, -26.2985249],
      [-48.8570521, -26.2985136],
      [-48.8569732, -26.2985025],
      [-48.85688, -26.2984995],
      [-48.8567652, -26.2985063],
      [-48.8559888, -26.2986093],
      [-48.8558735, -26.2986237],
      [-48.8555722, -26.2986612],
      [-48.8552673, -26.2986997]
    ],
    [
      [-48.8642815, -26.2965609],
      [-48.8635834, -26.2966686],
      [-48.8630465, -26.2967597],
      [-48.8629778, -26.2967703],
      [-48.8629338, -26.2967785],
      [-48.8624117, -26.2968667],
      [-48.8622417, -26.2969013]
    ],
    [
      [-48.8294323, -26.3606424],
      [-48.8292924, -26.3606545],
      [-48.8291459, -26.3606677],
      [-48.8287883, -26.3606991],
      [-48.8286196, -26.3607143],
      [-48.8285211, -26.3607218]
    ],
    [
      [-48.9015247, -26.3314579],
      [-48.9036097, -26.3295153]
    ],
    [
      [-48.8547424, -26.2535264],
      [-48.8546053, -26.2535362]
    ],
    [
      [-48.8479548, -26.2948289],
      [-48.8480378, -26.2948235],
      [-48.8500705, -26.2946895],
      [-48.8502181, -26.2946798]
    ],
    [
      [-48.9057457, -26.2916724],
      [-48.9053689, -26.2916538]
    ],
    [
      [-48.8851543, -26.2952095],
      [-48.8851415, -26.2950869],
      [-48.8851427, -26.2950113],
      [-48.8851617, -26.294925],
      [-48.8851936, -26.2948616],
      [-48.88524, -26.2947926],
      [-48.8853064, -26.2947235],
      [-48.8853889, -26.2946617],
      [-48.8854846, -26.2945972],
      [-48.88565, -26.2944947]
    ],
    [
      [-48.8986794, -26.2872749],
      [-48.8987702, -26.2872676],
      [-48.8988728, -26.2872629],
      [-48.8989806, -26.2872634],
      [-48.899571, -26.2872827],
      [-48.8995975, -26.2872846],
      [-48.8997249, -26.2872904],
      [-48.8999301, -26.2872999],
      [-48.9004414, -26.2873233]
    ],
    [
      [-48.9004414, -26.2873233],
      [-48.9007914, -26.2873395],
      [-48.9014143, -26.2873684],
      [-48.9016107, -26.287377],
      [-48.9020416, -26.2873974],
      [-48.902142, -26.2874014],
      [-48.9022435, -26.2874015],
      [-48.9023342, -26.2873981]
    ],
    [
      [-48.9045911, -26.292328],
      [-48.9040607, -26.2923669],
      [-48.9038091, -26.2923799],
      [-48.903549, -26.2923851],
      [-48.9033275, -26.2923833],
      [-48.9027731, -26.2923687],
      [-48.9020576, -26.2923413],
      [-48.9011437, -26.2923049],
      [-48.9004615, -26.2922753],
      [-48.9001764, -26.292263]
    ],
    [
      [-48.9178389, -26.2873069],
      [-48.9187046, -26.287347],
      [-48.9195448, -26.2873859],
      [-48.9205467, -26.2874323]
    ],
    [
      [-48.9067232, -26.286795],
      [-48.9073039, -26.286727],
      [-48.9074478, -26.2867137],
      [-48.9075506, -26.2867053],
      [-48.907641, -26.2866998],
      [-48.9077458, -26.2866978],
      [-48.9078318, -26.2867014],
      [-48.9079281, -26.2867098],
      [-48.9080134, -26.2867184],
      [-48.9087251, -26.2868127],
      [-48.9090359, -26.2868509],
      [-48.9092514, -26.286875],
      [-48.9094902, -26.2868982],
      [-48.9098157, -26.2869281]
    ],
    [
      [-48.9098157, -26.2869281],
      [-48.9102558, -26.2869535],
      [-48.9106538, -26.286974],
      [-48.9113714, -26.2870065],
      [-48.9119784, -26.2870354],
      [-48.9120798, -26.2870399],
      [-48.9132958, -26.2870964],
      [-48.9133676, -26.2870995],
      [-48.9141934, -26.2871378],
      [-48.9144904, -26.2871516],
      [-48.9160761, -26.2872252],
      [-48.9163029, -26.2872357],
      [-48.9170678, -26.2872712],
      [-48.9178389, -26.2873069]
    ],
    [
      [-48.8520977, -26.2525762],
      [-48.8521709, -26.2525571],
      [-48.8522295, -26.2525484],
      [-48.8522945, -26.2525525],
      [-48.8523487, -26.2525649],
      [-48.8523947, -26.2525793]
    ],
    [
      [-48.8196901, -26.2774031],
      [-48.8194151, -26.2774359],
      [-48.8192389, -26.2774108],
      [-48.8190885, -26.2773646],
      [-48.8189703, -26.2772952],
      [-48.8188586, -26.2771912],
      [-48.8187705, -26.2770583],
      [-48.8187039, -26.2769138],
      [-48.8186717, -26.2767596],
      [-48.8187232, -26.2766421]
    ],
    [
      [-48.8187232, -26.2766421],
      [-48.8188627, -26.2765998],
      [-48.8190047, -26.2765651],
      [-48.8191465, -26.2765458],
      [-48.8192862, -26.2765381],
      [-48.8194172, -26.2765535],
      [-48.8195526, -26.2765863],
      [-48.8196536, -26.2766441],
      [-48.8197223, -26.276725],
      [-48.8197696, -26.2767963],
      [-48.8197954, -26.2768926],
      [-48.8197954, -26.2769966],
      [-48.8197739, -26.2771199],
      [-48.8197438, -26.2772297],
      [-48.8197137, -26.2773184],
      [-48.8196901, -26.2774031]
    ],
    [
      [-48.8196901, -26.2774031],
      [-48.8191444, -26.2769311]
    ],
    [
      [-48.8191444, -26.2769311],
      [-48.8187232, -26.2766421]
    ],
    [
      [-48.8192131, -26.2768618],
      [-48.8191444, -26.2769311]
    ],
    [
      [-48.8187232, -26.2766421],
      [-48.8180967, -26.2767591],
      [-48.8175211, -26.2768385],
      [-48.8174281, -26.2768523]
    ],
    [
      [-48.8721237, -26.2736444],
      [-48.8721268, -26.2735583],
      [-48.8721294, -26.2734885],
      [-48.8721456, -26.2730423],
      [-48.8721491, -26.2729454],
      [-48.8721758, -26.2722142],
      [-48.8722026, -26.2714783],
      [-48.8722039, -26.2714431],
      [-48.8722279, -26.2707841],
      [-48.8722299, -26.270729],
      [-48.872252, -26.270123],
      [-48.8722575, -26.269972],
      [-48.8722661, -26.2697348],
      [-48.8722755, -26.2694783],
      [-48.8722989, -26.2688357]
    ],
    [
      [-48.8757472, -26.319738],
      [-48.8756981, -26.3194025],
      [-48.8756614, -26.3191586],
      [-48.8755614, -26.3185229]
    ],
    [
      [-48.8414754, -26.3397148],
      [-48.8414795, -26.3396109]
    ],
    [
      [-48.8414795, -26.3396109],
      [-48.8414836, -26.3395529],
      [-48.8414931, -26.3393309]
    ],
    [
      [-48.8317521, -26.3604665],
      [-48.8310348, -26.3605147],
      [-48.8309295, -26.3605214],
      [-48.830285, -26.3605683],
      [-48.83021, -26.3605738],
      [-48.8298485, -26.3606045],
      [-48.8296925, -26.3606171],
      [-48.8294323, -26.3606424]
    ],
    [
      [-48.8645048, -26.3000055],
      [-48.8644654, -26.3001095],
      [-48.8643939, -26.3002422],
      [-48.8642975, -26.3003861],
      [-48.8634128, -26.3016847],
      [-48.8629948, -26.3022882],
      [-48.86292, -26.3023982],
      [-48.8628303, -26.3025519],
      [-48.8627996, -26.3026269],
      [-48.862754, -26.3027501],
      [-48.8627068, -26.302898],
      [-48.8626721, -26.3030255],
      [-48.8626318, -26.3031989],
      [-48.8626143, -26.3033153],
      [-48.8626006, -26.3034065],
      [-48.8625967, -26.3034941],
      [-48.8625957, -26.3036391],
      [-48.8625981, -26.3037113]
    ],
    [
      [-48.8504624, -26.3034664],
      [-48.8504383, -26.3034976],
      [-48.8504303, -26.3035193],
      [-48.8504303, -26.3035722],
      [-48.85043, -26.3036234]
    ],
    [
      [-48.8504624, -26.3034664],
      [-48.8503885, -26.303477],
      [-48.8503375, -26.3034774],
      [-48.8502883, -26.3034655],
      [-48.8502325, -26.3034533]
    ],
    [
      [-48.8162692, -26.3918219],
      [-48.8161816, -26.391986],
      [-48.8160824, -26.3922278],
      [-48.8160416, -26.3923285],
      [-48.8160266, -26.3923672],
      [-48.8159905, -26.3924134],
      [-48.8159307, -26.392442],
      [-48.8158032, -26.3924718],
      [-48.8157235, -26.3924926],
      [-48.8156409, -26.3925497],
      [-48.8154698, -26.392726],
      [-48.8149006, -26.3933127],
      [-48.8148543, -26.3933841],
      [-48.8148094, -26.3934879],
      [-48.8147917, -26.3935985],
      [-48.8147819, -26.3936456],
      [-48.8147506, -26.3936854],
      [-48.8146894, -26.3937217],
      [-48.8145178, -26.3937705],
      [-48.8144033, -26.3938185],
      [-48.8142399, -26.3939122]
    ],
    [
      [-48.8947377, -26.2251976],
      [-48.8947971, -26.2252185],
      [-48.895744, -26.2255216],
      [-48.8958554, -26.225537],
      [-48.8959589, -26.2255349],
      [-48.8968739, -26.2254082],
      [-48.8972272, -26.2253588],
      [-48.8973758, -26.2253403],
      [-48.8974908, -26.2253351],
      [-48.897592, -26.2253607],
      [-48.8976971, -26.225415],
      [-48.8978017, -26.2254768],
      [-48.8989735, -26.2262258],
      [-48.9007647, -26.2273244]
    ],
    [
      [-48.8355877, -26.3125843],
      [-48.8355825, -26.3127178],
      [-48.8355272, -26.3141338],
      [-48.835522, -26.3142698],
      [-48.8355169, -26.3143993],
      [-48.8354642, -26.3157481],
      [-48.8354588, -26.3158945],
      [-48.8354361, -26.3164682]
    ],
    [
      [-48.8397757, -26.3069813],
      [-48.8397729, -26.3070413],
      [-48.8397381, -26.3077674],
      [-48.8396775, -26.309032],
      [-48.8396761, -26.3090617]
    ],
    [
      [-48.8327316, -26.3213449],
      [-48.8328773, -26.3214879],
      [-48.8329684, -26.3215719],
      [-48.8330656, -26.3216511],
      [-48.8331677, -26.3217209],
      [-48.8336667, -26.3220351],
      [-48.8339425, -26.3222087],
      [-48.8343163, -26.3224441],
      [-48.8348179, -26.3227599],
      [-48.8349179, -26.3228228],
      [-48.8355027, -26.3231911],
      [-48.8360968, -26.3235651],
      [-48.8362784, -26.3236794],
      [-48.8365641, -26.3238593],
      [-48.8366861, -26.3239361],
      [-48.8371906, -26.3242537],
      [-48.8372846, -26.3243132]
    ],
    [
      [-48.8326066, -26.3212108],
      [-48.8327316, -26.3213449]
    ],
    [
      [-48.8324665, -26.3213685],
      [-48.8319149, -26.3219892],
      [-48.8313948, -26.3225745],
      [-48.8311282, -26.3228745],
      [-48.8310021, -26.3230164],
      [-48.8305588, -26.3235152],
      [-48.8301452, -26.3239806],
      [-48.8294285, -26.3247871]
    ],
    [
      [-48.8482922, -26.3168717],
      [-48.8483556, -26.316811],
      [-48.8494564, -26.3157561],
      [-48.8503528, -26.314897],
      [-48.8505837, -26.3146757],
      [-48.8509654, -26.3143099],
      [-48.8520205, -26.3132989],
      [-48.8530968, -26.3122674]
    ],
    [
      [-48.891863, -26.2905186],
      [-48.891951, -26.2904367],
      [-48.8921168, -26.2903588],
      [-48.892352, -26.2902483],
      [-48.8925509, -26.2901548],
      [-48.8945822, -26.2891409],
      [-48.895395, -26.2887271],
      [-48.8960814, -26.2883776],
      [-48.8963005, -26.2882661],
      [-48.8965474, -26.2881415]
    ],
    [
      [-48.9204017, -26.2921037],
      [-48.9193623, -26.2920562],
      [-48.9182266, -26.2920107],
      [-48.9176092, -26.291984],
      [-48.9160356, -26.2919164],
      [-48.9155653, -26.2918964],
      [-48.9154664, -26.2918965],
      [-48.9153762, -26.2919023]
    ],
    [
      [-48.9001764, -26.292263],
      [-48.8981904, -26.2921633]
    ],
    [
      [-48.8264912, -26.2734842],
      [-48.8258898, -26.273022],
      [-48.8258017, -26.2729529]
    ],
    [
      [-48.8279969, -26.2736546],
      [-48.8278572, -26.2736152],
      [-48.8277282, -26.2735894],
      [-48.8275903, -26.2735736],
      [-48.8274732, -26.2735695],
      [-48.8273912, -26.2735698]
    ],
    [
      [-48.8177042, -26.2815787],
      [-48.8171002, -26.282222],
      [-48.8165458, -26.2828126]
    ],
    [
      [-48.8144684, -26.2792879],
      [-48.8143951, -26.279354],
      [-48.813931, -26.2798952],
      [-48.8134869, -26.2804097],
      [-48.8130405, -26.280926],
      [-48.812577, -26.2814558]
    ],
    [
      [-48.8418919, -26.2748808],
      [-48.8409206, -26.2745494],
      [-48.8407901, -26.2745281],
      [-48.8406988, -26.2745072],
      [-48.8405595, -26.2744559],
      [-48.8397307, -26.2740868]
    ],
    [
      [-48.8396476, -26.2705153],
      [-48.8399946, -26.2701798],
      [-48.8405059, -26.2696855],
      [-48.8407312, -26.2694714],
      [-48.8412016, -26.269016],
      [-48.8417612, -26.2684877],
      [-48.8418596, -26.2683857],
      [-48.8419335, -26.2683052],
      [-48.8420196, -26.2682026],
      [-48.8425659, -26.2675063]
    ],
    [
      [-48.8335429, -26.2752678],
      [-48.8338768, -26.2756421],
      [-48.8343045, -26.2761155],
      [-48.8343881, -26.2762205],
      [-48.83448, -26.2763463],
      [-48.834565, -26.2764819],
      [-48.834629, -26.2765853],
      [-48.8346899, -26.2766883],
      [-48.8347618, -26.2768119],
      [-48.8349094, -26.2770696]
    ],
    [
      [-48.8349094, -26.2770696],
      [-48.8351253, -26.2774575],
      [-48.8354949, -26.2781137],
      [-48.8356527, -26.2783499],
      [-48.8357671, -26.2784952],
      [-48.8358736, -26.2786118],
      [-48.8359678, -26.2787114],
      [-48.836132, -26.2788806],
      [-48.8364636, -26.2792312],
      [-48.8365491, -26.279347],
      [-48.8366186, -26.2794591],
      [-48.836741, -26.2796723]
    ],
    [
      [-48.8396476, -26.2705153],
      [-48.8398625, -26.2708896],
      [-48.8399751, -26.2710681],
      [-48.8400671, -26.2711946],
      [-48.8401754, -26.2713377],
      [-48.8403606, -26.2715638],
      [-48.8413331, -26.2727485]
    ],
    [
      [-48.8108606, -26.2826253],
      [-48.810892, -26.282195],
      [-48.8109642, -26.2812051],
      [-48.81102, -26.2804393],
      [-48.8110559, -26.2799469],
      [-48.8111141, -26.2791496],
      [-48.8111213, -26.2790504]
    ],
    [
      [-48.8092519, -26.2676258],
      [-48.808735, -26.2669083],
      [-48.8083777, -26.2663997]
    ],
    [
      [-48.8224493, -26.2712519],
      [-48.8221791, -26.2706883],
      [-48.8221375, -26.2705954],
      [-48.8221092, -26.2705065],
      [-48.8220966, -26.2704427],
      [-48.8220895, -26.2703668]
    ],
    [
      [-48.8102171, -26.2784306],
      [-48.809645, -26.2780408],
      [-48.8090224, -26.2776166],
      [-48.8084411, -26.2772206],
      [-48.8083607, -26.2771658],
      [-48.8082979, -26.277123],
      [-48.8078808, -26.2768389],
      [-48.8077712, -26.2767641],
      [-48.8073267, -26.2764613],
      [-48.8067533, -26.2760707],
      [-48.8061931, -26.275689],
      [-48.8056049, -26.2752882]
    ],
    [
      [-48.8015768, -26.2725438],
      [-48.8009361, -26.2721071],
      [-48.8003478, -26.2717063]
    ],
    [
      [-48.8050233, -26.274892],
      [-48.804457, -26.2745062],
      [-48.8038804, -26.2741132],
      [-48.8033151, -26.273728],
      [-48.802719, -26.2733221]
    ],
    [
      [-48.8221293, -26.2700949],
      [-48.8221743, -26.2698896],
      [-48.8222404, -26.269537],
      [-48.8222903, -26.269241],
      [-48.8223392, -26.2689028],
      [-48.8223644, -26.2687248],
      [-48.8223863, -26.2685342],
      [-48.8223922, -26.2684484],
      [-48.8224014, -26.2683396],
      [-48.822405, -26.2682537],
      [-48.8224006, -26.268155],
      [-48.8223954, -26.268103],
      [-48.8223796, -26.2680152],
      [-48.8223605, -26.267946],
      [-48.8221911, -26.2674359]
    ],
    [
      [-48.8197007, -26.2518232],
      [-48.8198044, -26.2515113],
      [-48.8198362, -26.251426],
      [-48.8198649, -26.2513547],
      [-48.8198872, -26.2513059],
      [-48.8199307, -26.2512278],
      [-48.8199938, -26.2511343],
      [-48.8200112, -26.251113]
    ],
    [
      [-48.8198763, -26.2586744],
      [-48.8199373, -26.2585555],
      [-48.8200094, -26.2584154],
      [-48.8201784, -26.258095],
      [-48.820227, -26.2579994],
      [-48.8202637, -26.2579277],
      [-48.8203516, -26.2577538],
      [-48.8203948, -26.2576594],
      [-48.8204269, -26.257571],
      [-48.8204544, -26.257469],
      [-48.8204787, -26.2573704],
      [-48.8204946, -26.2572709],
      [-48.8205059, -26.2571546],
      [-48.8205064, -26.2570308],
      [-48.8204988, -26.2568892],
      [-48.8204604, -26.2565048],
      [-48.8204271, -26.2562174],
      [-48.8203959, -26.2559939],
      [-48.8203756, -26.2558601],
      [-48.8203396, -26.2557026],
      [-48.8200623, -26.2548061],
      [-48.8200348, -26.2547107],
      [-48.8200017, -26.2546242],
      [-48.8199617, -26.2545377],
      [-48.8199, -26.2544397],
      [-48.8198337, -26.2543619],
      [-48.8197471, -26.2542601],
      [-48.8192402, -26.2537204],
      [-48.8191979, -26.2536558],
      [-48.8191684, -26.2535696],
      [-48.8191674, -26.2535168],
      [-48.8191771, -26.2534502],
      [-48.8191898, -26.2533987]
    ],
    [
      [-48.8198854, -26.2430658],
      [-48.8195385, -26.2420749],
      [-48.8194077, -26.2416936],
      [-48.8192952, -26.2413654]
    ],
    [
      [-48.8210137, -26.2495354],
      [-48.8211804, -26.2491662],
      [-48.821291, -26.2489009],
      [-48.8213517, -26.2487175],
      [-48.8213946, -26.2485491],
      [-48.8214215, -26.2482652]
    ],
    [
      [-48.8180442, -26.2369704],
      [-48.8179696, -26.2366473],
      [-48.8178992, -26.236308]
    ],
    [
      [-48.8192952, -26.2413654],
      [-48.819037, -26.2406115],
      [-48.8187307, -26.2397328],
      [-48.8185711, -26.2392051],
      [-48.8184845, -26.2388734],
      [-48.8183206, -26.2382144]
    ],
    [
      [-48.8236671, -26.2126626],
      [-48.8248646, -26.2114127],
      [-48.8253293, -26.2109275],
      [-48.8257921, -26.2104445],
      [-48.8262693, -26.2099464],
      [-48.8266783, -26.2095195],
      [-48.8270992, -26.2090802],
      [-48.8275208, -26.2086401],
      [-48.8279397, -26.2082028],
      [-48.8283673, -26.2077564],
      [-48.828781, -26.2073246],
      [-48.8288625, -26.2072396],
      [-48.8291929, -26.2068947]
    ],
    [
      [-48.8210782, -26.2153648],
      [-48.8236671, -26.2126626]
    ],
    [
      [-48.8291929, -26.2068947],
      [-48.8293997, -26.2066788],
      [-48.8295275, -26.2065454],
      [-48.8299658, -26.2060879],
      [-48.8308408, -26.2051745],
      [-48.8312927, -26.2047028]
    ],
    [
      [-48.8265861, -26.2710177],
      [-48.8268265, -26.271174]
    ],
    [
      [-48.8260591, -26.2705583],
      [-48.8263465, -26.2708088],
      [-48.8263729, -26.2708319]
    ],
    [
      [-48.8183206, -26.2382144],
      [-48.8181972, -26.2376611],
      [-48.8181792, -26.2375803]
    ],
    [
      [-48.8220895, -26.2703668],
      [-48.822106, -26.2702109],
      [-48.8221293, -26.2700949]
    ],
    [
      [-48.8433025, -26.2874557],
      [-48.8431805, -26.2874614]
    ],
    [
      [-48.8191898, -26.2533987],
      [-48.8193742, -26.2528301],
      [-48.8194926, -26.2524651],
      [-48.8195375, -26.2523264],
      [-48.8195613, -26.2522533],
      [-48.8197007, -26.2518232]
    ],
    [
      [-48.8903685, -26.1951385],
      [-48.8903941, -26.1951199]
    ],
    [
      [-48.836741, -26.2796723],
      [-48.836926, -26.2799843],
      [-48.8370101, -26.2801262],
      [-48.8370942, -26.280268]
    ],
    [
      [-48.88168, -26.2845004],
      [-48.8809901, -26.2845327],
      [-48.88077, -26.284543]
    ],
    [
      [-48.8825361, -26.2844603],
      [-48.88168, -26.2845004]
    ],
    [
      [-48.8390206, -26.267087],
      [-48.839147, -26.2670707],
      [-48.8399736, -26.2669644],
      [-48.8408249, -26.2668549],
      [-48.8426414, -26.2666212],
      [-48.8448619, -26.2663356],
      [-48.8449666, -26.2663221]
    ],
    [
      [-48.8677659, -26.2885769],
      [-48.8678539, -26.289394],
      [-48.8678695, -26.2895387],
      [-48.8679385, -26.290179],
      [-48.867947, -26.2902584],
      [-48.8680232, -26.2909653],
      [-48.8680345, -26.2911084],
      [-48.8680496, -26.2914435],
      [-48.8680786, -26.2920877],
      [-48.868099, -26.2925398]
    ],
    [
      [-48.8743419, -26.2646593],
      [-48.8744626, -26.2646746],
      [-48.874599, -26.2647012],
      [-48.8747086, -26.2647304],
      [-48.8748428, -26.2647743],
      [-48.8750198, -26.2648451],
      [-48.8751896, -26.264931],
      [-48.8753653, -26.2650352],
      [-48.8755363, -26.2651493],
      [-48.8761819, -26.2656372],
      [-48.8765715, -26.2659276],
      [-48.8770507, -26.2662848],
      [-48.8771393, -26.2663379],
      [-48.8772137, -26.2663721],
      [-48.877276, -26.2663965],
      [-48.8773343, -26.2664158],
      [-48.8774179, -26.2664354],
      [-48.8775124, -26.266449],
      [-48.8779441, -26.2665115],
      [-48.8781566, -26.2665384],
      [-48.8782226, -26.266545],
      [-48.8782989, -26.2665516],
      [-48.8783734, -26.2665508],
      [-48.8784655, -26.2665405],
      [-48.8785608, -26.2665175],
      [-48.8786334, -26.2664951],
      [-48.8787086, -26.2664672],
      [-48.8792419, -26.2662272],
      [-48.8794044, -26.2661447],
      [-48.8797212, -26.2659839]
    ],
    [
      [-48.8505995, -26.2534974],
      [-48.8506533, -26.2534718],
      [-48.8506432, -26.25345],
      [-48.8506449, -26.2534258],
      [-48.8506676, -26.2533995],
      [-48.8506962, -26.2533806],
      [-48.8515922, -26.2529636],
      [-48.8521784, -26.2526754],
      [-48.8522081, -26.2526621],
      [-48.8522469, -26.2526631],
      [-48.8523603, -26.2526951]
    ],
    [
      [-48.8405841, -26.3161738],
      [-48.8405074, -26.3161699],
      [-48.8403907, -26.3161634],
      [-48.8398422, -26.3161335],
      [-48.8394521, -26.3161122],
      [-48.8393388, -26.3161062],
      [-48.8388542, -26.3160796],
      [-48.8386419, -26.3160681],
      [-48.8385647, -26.3160638],
      [-48.8383293, -26.316051],
      [-48.8375382, -26.3160079],
      [-48.8365051, -26.3159516],
      [-48.8355773, -26.315901],
      [-48.8354588, -26.3158945],
      [-48.8347131, -26.3158539],
      [-48.8342361, -26.3158279],
      [-48.8327452, -26.3157466]
    ],
    [
      [-48.8448275, -26.2390771],
      [-48.8451902, -26.2373133],
      [-48.845818, -26.2342599],
      [-48.8459874, -26.2334361],
      [-48.8460446, -26.2333107],
      [-48.8461143, -26.2332],
      [-48.8462538, -26.2330316],
      [-48.8464094, -26.2329354],
      [-48.8468103, -26.2326754],
      [-48.8477973, -26.2320353],
      [-48.8486602, -26.2314485],
      [-48.8499489, -26.2305451],
      [-48.8505618, -26.2302335],
      [-48.8516924, -26.2296904],
      [-48.8536638, -26.2287923],
      [-48.8551135, -26.228091],
      [-48.8552369, -26.2280525],
      [-48.8554139, -26.2280188],
      [-48.8555286, -26.22802],
      [-48.8556285, -26.2280296],
      [-48.8558565, -26.2280886],
      [-48.8565914, -26.2282914],
      [-48.8568575, -26.2283713],
      [-48.857274, -26.2284758],
      [-48.8577922, -26.2286114],
      [-48.85802, -26.228671],
      [-48.8581931, -26.2287163],
      [-48.8590486, -26.2289373],
      [-48.8627934, -26.2299024],
      [-48.8632849, -26.230029],
      [-48.8636587, -26.2301282],
      [-48.8643262, -26.2303006],
      [-48.8644876, -26.230333],
      [-48.8646592, -26.2303412],
      [-48.8648197, -26.2303198],
      [-48.8649444, -26.230269],
      [-48.8650557, -26.2302236],
      [-48.8661153, -26.2296651],
      [-48.8661696, -26.229635],
      [-48.8668495, -26.2293084],
      [-48.8671459, -26.2291701],
      [-48.8686282, -26.2284775],
      [-48.8689765, -26.2283147],
      [-48.8692662, -26.2281848],
      [-48.8695358, -26.2280356],
      [-48.8697712, -26.2278698],
      [-48.8700207, -26.227597],
      [-48.8707336, -26.2267836]
    ],
    [
      [-48.9046245, -26.1494121],
      [-48.9046304, -26.1493593],
      [-48.9046285, -26.1492825],
      [-48.9046116, -26.1491976],
      [-48.904574, -26.1490828],
      [-48.9045231, -26.1489763],
      [-48.9044722, -26.1489039],
      [-48.9044079, -26.1488301],
      [-48.9043197, -26.1487515],
      [-48.904153, -26.1486324]
    ],
    [
      [-48.8132985, -26.2912739],
      [-48.8129627, -26.2909274],
      [-48.8125783, -26.2905307],
      [-48.8125409, -26.290492],
      [-48.8125057, -26.2904557],
      [-48.8124775, -26.2904266],
      [-48.8124479, -26.2903961],
      [-48.8124184, -26.2903656],
      [-48.8123483, -26.2902933],
      [-48.8122995, -26.2902429]
    ],
    [
      [-48.8111213, -26.2790504],
      [-48.8112439, -26.2773689]
    ],
    [
      [-48.8262397, -26.3065941],
      [-48.8259618, -26.3061823],
      [-48.8258703, -26.3060467],
      [-48.8256664, -26.3057444],
      [-48.8256275, -26.3056867],
      [-48.8252549, -26.3051346],
      [-48.8250543, -26.3048372],
      [-48.8247748, -26.304423],
      [-48.8245562, -26.3040991],
      [-48.8239624, -26.303219],
      [-48.8235316, -26.3025806],
      [-48.8231425, -26.3020039],
      [-48.8230295, -26.3018364],
      [-48.8228653, -26.3016004],
      [-48.8227694, -26.3014694],
      [-48.8227113, -26.3013934],
      [-48.8226423, -26.3013096],
      [-48.8225749, -26.3012355],
      [-48.8221681, -26.3008233],
      [-48.821797, -26.3004573],
      [-48.8217102, -26.3003733],
      [-48.8216062, -26.300268],
      [-48.8215065, -26.3001643],
      [-48.8214277, -26.3000708],
      [-48.8213305, -26.2999424],
      [-48.8211364, -26.2996483],
      [-48.820963, -26.299386],
      [-48.8209183, -26.2993209],
      [-48.8206624, -26.298939],
      [-48.8203405, -26.2984713],
      [-48.8202598, -26.2983685],
      [-48.8201906, -26.2982883],
      [-48.8200465, -26.2981361]
    ],
    [
      [-48.8189456, -26.296043],
      [-48.8190175, -26.2961104],
      [-48.8195015, -26.2965636],
      [-48.8195596, -26.296618],
      [-48.8201469, -26.297168],
      [-48.8206316, -26.2976219],
      [-48.8210068, -26.2979736],
      [-48.8214997, -26.298435],
      [-48.8221263, -26.2990218],
      [-48.8225522, -26.2994206],
      [-48.8230065, -26.2998461],
      [-48.8236244, -26.3004247],
      [-48.8237214, -26.3005155],
      [-48.8239642, -26.300743],
      [-48.8240764, -26.3008481],
      [-48.8246468, -26.3013822],
      [-48.8251775, -26.3018791],
      [-48.8258122, -26.3024736],
      [-48.8265584, -26.3031724],
      [-48.8278897, -26.3044191],
      [-48.8283599, -26.3048594],
      [-48.8286689, -26.3051487],
      [-48.8288365, -26.3053057],
      [-48.8293867, -26.3058209]
    ],
    [
      [-48.7922355, -26.285087],
      [-48.7916753, -26.285078]
    ],
    [
      [-48.868099, -26.2925398],
      [-48.8681413, -26.2934797]
    ],
    [
      [-48.8501371, -26.2936854],
      [-48.8480795, -26.293816]
    ],
    [
      [-48.8128831, -26.3398827],
      [-48.8127197, -26.33983],
      [-48.8125966, -26.3397785],
      [-48.8123791, -26.339718],
      [-48.8122237, -26.3396866],
      [-48.8120614, -26.3396647],
      [-48.8118952, -26.3396542],
      [-48.8115761, -26.3396536],
      [-48.8108777, -26.3396451],
      [-48.8105103, -26.3396399],
      [-48.809877, -26.3396311],
      [-48.8096111, -26.3396272],
      [-48.809021, -26.339629],
      [-48.8088928, -26.3396286]
    ],
    [
      [-48.8047734, -26.3596457],
      [-48.8040646, -26.3596795]
    ],
    [
      [-48.8067009, -26.3595503],
      [-48.8054744, -26.359611],
      [-48.80513, -26.3596281],
      [-48.8047734, -26.3596457]
    ],
    [
      [-48.8426287, -26.3162855],
      [-48.8418295, -26.3162418],
      [-48.841356, -26.316216],
      [-48.8406678, -26.3161785],
      [-48.8405841, -26.3161738]
    ],
    [
      [-48.9074055, -26.3296298],
      [-48.9068406, -26.3290897],
      [-48.9063381, -26.3286201],
      [-48.9058504, -26.3281559],
      [-48.9053419, -26.3276871]
    ],
    [
      [-48.9015247, -26.3314579],
      [-48.901034, -26.3309928],
      [-48.9005419, -26.3305171],
      [-48.9000848, -26.3300508],
      [-48.9000179, -26.3299587]
    ],
    [
      [-48.904096, -26.3345867],
      [-48.9040518, -26.3341539],
      [-48.9040456, -26.3340838],
      [-48.904037, -26.3340076],
      [-48.9040263, -26.3339635],
      [-48.9039972, -26.333893],
      [-48.9039692, -26.3338376],
      [-48.9039368, -26.3337855],
      [-48.9039053, -26.3337438],
      [-48.9038602, -26.3336929],
      [-48.9035061, -26.3333515],
      [-48.9030248, -26.3328853],
      [-48.9025399, -26.3324164],
      [-48.9020258, -26.331927],
      [-48.9015247, -26.3314579]
    ],
    [
      [-48.8426287, -26.3162855],
      [-48.8426894, -26.3149753],
      [-48.8427013, -26.3147173],
      [-48.8427069, -26.3145954]
    ],
    [
      [-48.8767154, -26.332672],
      [-48.8767471, -26.3322673],
      [-48.8768536, -26.330893],
      [-48.8768681, -26.3307065]
    ],
    [
      [-48.9036097, -26.3295153],
      [-48.9038845, -26.328955],
      [-48.9043539, -26.3285577],
      [-48.9048138, -26.3281515],
      [-48.9053419, -26.3276871]
    ],
    [
      [-48.9102843, -26.3220077],
      [-48.9104199, -26.3218791],
      [-48.9107815, -26.3215193],
      [-48.911281, -26.3210296],
      [-48.9118501, -26.3204615],
      [-48.9122305, -26.3200842],
      [-48.9141378, -26.318216],
      [-48.9157727, -26.3166208],
      [-48.9187956, -26.3136657],
      [-48.9199646, -26.312523],
      [-48.9220926, -26.3104427],
      [-48.9221587, -26.310378]
    ],
    [
      [-48.88077, -26.284543],
      [-48.8798398, -26.2845866],
      [-48.8791268, -26.2846199],
      [-48.8790318, -26.2846244],
      [-48.8787941, -26.2846355],
      [-48.8781743, -26.2846646],
      [-48.877976, -26.2846738],
      [-48.8775288, -26.2846948],
      [-48.876974, -26.2847208],
      [-48.8767172, -26.2847337],
      [-48.875935, -26.2847694],
      [-48.8758633, -26.2847728]
    ],
    [
      [-48.8768681, -26.3307065],
      [-48.8769309, -26.3300603],
      [-48.8769396, -26.329908],
      [-48.8769472, -26.3297546],
      [-48.8769444, -26.3296581],
      [-48.8769332, -26.3295737],
      [-48.8767733, -26.3288328],
      [-48.876717, -26.3285814],
      [-48.876685, -26.3284415],
      [-48.8766521, -26.3283299],
      [-48.8766158, -26.328227],
      [-48.8765775, -26.3281565],
      [-48.8765205, -26.3280704],
      [-48.8762533, -26.3277552],
      [-48.8761866, -26.327658],
      [-48.8761381, -26.3275697],
      [-48.8761096, -26.3274977],
      [-48.8760873, -26.3274034],
      [-48.8760744, -26.3273246],
      [-48.8760717, -26.3272352],
      [-48.8760875, -26.3271371],
      [-48.8761805, -26.3267703],
      [-48.8763898, -26.3258854],
      [-48.8765076, -26.3253119],
      [-48.8765304, -26.3251929],
      [-48.8765537, -26.3250603],
      [-48.876572, -26.3249199],
      [-48.8765758, -26.3248329],
      [-48.8765679, -26.3247326],
      [-48.8765518, -26.324652],
      [-48.8765242, -26.3245708],
      [-48.8764845, -26.3244917],
      [-48.8763869, -26.3243383],
      [-48.8754173, -26.3228947],
      [-48.8752939, -26.3227144],
      [-48.8752337, -26.3226102],
      [-48.8751906, -26.322504],
      [-48.8751722, -26.3224053],
      [-48.8751638, -26.3223105],
      [-48.8751705, -26.3222023],
      [-48.8751933, -26.3221273],
      [-48.8752313, -26.3220496],
      [-48.8752818, -26.3219775],
      [-48.8753401, -26.3219056],
      [-48.875609, -26.3216217],
      [-48.875658, -26.3215571],
      [-48.8757009, -26.3214906],
      [-48.8757328, -26.3214317],
      [-48.8757592, -26.3213642],
      [-48.8757807, -26.3213128],
      [-48.8758107, -26.3212274],
      [-48.8758317, -26.3211312],
      [-48.8758463, -26.3210362],
      [-48.8758665, -26.3208812],
      [-48.8758773, -26.3207189],
      [-48.8758754, -26.3206036],
      [-48.8758625, -26.3204833],
      [-48.875802, -26.3200875],
      [-48.8757808, -26.3199524],
      [-48.8757472, -26.319738]
    ],
    [
      [-48.8275565, -26.3077004],
      [-48.8278173, -26.3074768],
      [-48.8286294, -26.3067808]
    ],
    [
      [-48.8273364, -26.307913],
      [-48.8270929, -26.3077723]
    ],
    [
      [-48.8270469, -26.3077904],
      [-48.8270929, -26.3077723],
      [-48.8271264, -26.307734]
    ],
    [
      [-48.8292566, -26.3062432],
      [-48.8293642, -26.3062065],
      [-48.8294489, -26.3061831],
      [-48.8295388, -26.3061703],
      [-48.8295779, -26.3061698],
      [-48.8296375, -26.3061691],
      [-48.8297814, -26.3061803]
    ],
    [
      [-48.8200393, -26.3063336],
      [-48.8199724, -26.3063448],
      [-48.8191479, -26.3056784],
      [-48.8190009, -26.3055242],
      [-48.8184528, -26.304966],
      [-48.8181866, -26.3048021],
      [-48.8179356, -26.3046687],
      [-48.8173691, -26.3044216],
      [-48.817058, -26.3043181],
      [-48.8168248, -26.3042712],
      [-48.8165985, -26.3042435],
      [-48.8163233, -26.3042557],
      [-48.8159691, -26.30431],
      [-48.8155141, -26.3044115],
      [-48.8145155, -26.3046249],
      [-48.814374, -26.3045942],
      [-48.8141893, -26.304519]
    ],
    [
      [-48.8538426, -26.292114],
      [-48.8538719, -26.2924502],
      [-48.8539546, -26.2933987],
      [-48.8539583, -26.2934416]
    ],
    [
      [-48.8142399, -26.3939122],
      [-48.8140956, -26.3940577],
      [-48.8139859, -26.3941652],
      [-48.8138571, -26.3942716],
      [-48.8137377, -26.3943543],
      [-48.8136071, -26.3944267],
      [-48.8134283, -26.3945148],
      [-48.8132471, -26.3945847],
      [-48.8130516, -26.3946503],
      [-48.8128913, -26.3946967],
      [-48.8127491, -26.3947294],
      [-48.8125112, -26.3947638]
    ],
    [
      [-48.8554805, -26.254349],
      [-48.8558995, -26.2543603]
    ],
    [
      [-48.8429639, -26.3090431],
      [-48.8429774, -26.3087543],
      [-48.8430344, -26.3075341],
      [-48.8430399, -26.3074165]
    ],
    [
      [-48.8429591, -26.3091466],
      [-48.8429639, -26.3090431]
    ],
    [
      [-48.8502325, -26.3034533],
      [-48.8491175, -26.3024924]
    ],
    [
      [-48.85043, -26.3036234],
      [-48.8517159, -26.3047315],
      [-48.8523163, -26.3052489],
      [-48.8527075, -26.3055861],
      [-48.852825, -26.3056874]
    ],
    [
      [-48.8755747, -26.2737283],
      [-48.8756516, -26.27373],
      [-48.876073, -26.2737392],
      [-48.8761777, -26.2737384],
      [-48.8763167, -26.2737317],
      [-48.8766648, -26.2737043],
      [-48.876834, -26.2736916],
      [-48.8769785, -26.2736886],
      [-48.8771019, -26.2736928],
      [-48.8772098, -26.2737031],
      [-48.877483, -26.2737335],
      [-48.8777149, -26.273763],
      [-48.8778378, -26.2737725],
      [-48.878158, -26.2737843]
    ],
    [
      [-48.8431518, -26.2921149],
      [-48.8431535, -26.2920315]
    ],
    [
      [-48.8431535, -26.2920315],
      [-48.8431797, -26.2875972],
      [-48.84318, -26.2875537],
      [-48.8431805, -26.2874614]
    ],
    [
      [-48.8428223, -26.2874782],
      [-48.8427436, -26.2874819]
    ],
    [
      [-48.843086, -26.2874658],
      [-48.8428223, -26.2874782]
    ],
    [
      [-48.8430492, -26.2921255],
      [-48.8430498, -26.2920361]
    ],
    [
      [-48.8430498, -26.2920361],
      [-48.8430853, -26.2875455],
      [-48.843086, -26.2874658],
      [-48.8430877, -26.2873566],
      [-48.8431198, -26.2866602],
      [-48.8432062, -26.28559]
    ],
    [
      [-48.8540439, -26.2944236],
      [-48.8541433, -26.2955617],
      [-48.8542293, -26.2965503]
    ],
    [
      [-48.8455491, -26.2698658],
      [-48.8450246, -26.2700902],
      [-48.8448845, -26.2701536],
      [-48.8447673, -26.2702181],
      [-48.8446737, -26.2702775],
      [-48.8434944, -26.2711186],
      [-48.8434362, -26.2711616],
      [-48.8434067, -26.2711834],
      [-48.842681, -26.2717141],
      [-48.8426086, -26.271767],
      [-48.8422027, -26.2720742],
      [-48.8420287, -26.2722059],
      [-48.8418726, -26.2723276],
      [-48.841583, -26.2725519],
      [-48.8413331, -26.2727485]
    ],
    [
      [-48.8108711, -26.2699169],
      [-48.8103464, -26.2691753]
    ],
    [
      [-48.8433253, -26.2851898],
      [-48.8433333, -26.2850675],
      [-48.8433411, -26.2849748]
    ],
    [
      [-48.8413331, -26.2727485],
      [-48.8408279, -26.2731551],
      [-48.8407658, -26.2732051],
      [-48.8406299, -26.2733149],
      [-48.8404457, -26.2734636],
      [-48.8401518, -26.2737152],
      [-48.8397307, -26.2740868]
    ],
    [
      [-48.8488225, -26.2733761],
      [-48.8488536, -26.2733157],
      [-48.8488947, -26.273261],
      [-48.8491078, -26.2730704]
    ],
    [
      [-48.8494279, -26.2540405],
      [-48.8494858, -26.2539764],
      [-48.8495468, -26.2539177],
      [-48.8496136, -26.2538626],
      [-48.8496744, -26.2538221],
      [-48.8497444, -26.2537855],
      [-48.849833, -26.2537419]
    ],
    [
      [-48.8455491, -26.2698658],
      [-48.8455038, -26.2695899],
      [-48.8454169, -26.2690616],
      [-48.8454058, -26.2689941],
      [-48.8453414, -26.2686025],
      [-48.8453088, -26.2684037],
      [-48.8451502, -26.2674388]
    ],
    [
      [-48.8422993, -26.3232316],
      [-48.8423163, -26.3228886],
      [-48.842336, -26.3224905],
      [-48.8423446, -26.3223177],
      [-48.8423471, -26.3222686],
      [-48.8423495, -26.3222205],
      [-48.8424114, -26.3209724],
      [-48.8424174, -26.3208518]
    ],
    [
      [-48.8105959, -26.2860667],
      [-48.8107171, -26.2865215],
      [-48.8107343, -26.2865862],
      [-48.8110981, -26.2879513],
      [-48.8113094, -26.2887442],
      [-48.8113285, -26.2888081],
      [-48.8113518, -26.2888744],
      [-48.8113894, -26.2889543],
      [-48.8114502, -26.2890617],
      [-48.8115088, -26.28915],
      [-48.8115719, -26.2892219],
      [-48.8116615, -26.2893139],
      [-48.8119001, -26.289534],
      [-48.8119542, -26.289584],
      [-48.8123658, -26.2899639],
      [-48.8124552, -26.2900464],
      [-48.8124839, -26.2900729],
      [-48.8126976, -26.2902701],
      [-48.8131985, -26.2907325],
      [-48.8132713, -26.2907997]
    ],
    [
      [-48.8297814, -26.3061803],
      [-48.8299163, -26.3062658],
      [-48.8300398, -26.3063263],
      [-48.8302092, -26.3063865],
      [-48.8303597, -26.3064238],
      [-48.8305306, -26.3064496],
      [-48.8307718, -26.3064749],
      [-48.831361, -26.3065281],
      [-48.8319347, -26.3065799],
      [-48.8328148, -26.3066587],
      [-48.8329221, -26.3066683],
      [-48.8331085, -26.306684],
      [-48.8333182, -26.3067039],
      [-48.8335414, -26.3067348]
    ],
    [
      [-48.8021655, -26.2190299],
      [-48.8013737, -26.2191847],
      [-48.8011688, -26.2192185],
      [-48.8007644, -26.2192757],
      [-48.8006235, -26.2192927],
      [-48.8005468, -26.2193002],
      [-48.8004282, -26.2193059],
      [-48.8001803, -26.2193156],
      [-48.8000937, -26.2193237],
      [-48.799997, -26.2193405],
      [-48.7996853, -26.2194078],
      [-48.7993972, -26.2194795],
      [-48.799092, -26.2195554],
      [-48.7990121, -26.219563],
      [-48.7989349, -26.2195659],
      [-48.7988731, -26.2195644]
    ],
    [
      [-48.798719, -26.2194985],
      [-48.7986571, -26.2195628],
      [-48.7985849, -26.2195996],
      [-48.7985189, -26.2196174],
      [-48.7984302, -26.2196307],
      [-48.7980118, -26.2196668],
      [-48.7977342, -26.2197489],
      [-48.7970925, -26.2202788],
      [-48.7969293, -26.2204225],
      [-48.796777, -26.2205724],
      [-48.7964851, -26.2208811],
      [-48.7963059, -26.221032],
      [-48.7960855, -26.2211616],
      [-48.7957889, -26.2212995],
      [-48.7948881, -26.2216366],
      [-48.7947556, -26.2216586],
      [-48.7945737, -26.2216642],
      [-48.7944114, -26.2216546],
      [-48.7933801, -26.22152],
      [-48.7932549, -26.2215116],
      [-48.793095, -26.2215142],
      [-48.7929612, -26.221523],
      [-48.792708, -26.2215922],
      [-48.7926055, -26.2216202],
      [-48.7922554, -26.2217159],
      [-48.7921513, -26.2217652],
      [-48.7919334, -26.2219006],
      [-48.7916113, -26.2221006],
      [-48.7915141, -26.2221424],
      [-48.7910599, -26.222249],
      [-48.7908354, -26.2222428],
      [-48.7903719, -26.222097],
      [-48.7899572, -26.2221072],
      [-48.7897498, -26.2221604],
      [-48.7896486, -26.2221968],
      [-48.7894444, -26.2224262],
      [-48.7893239, -26.2226477],
      [-48.7892269, -26.2230905],
      [-48.7892372, -26.2234056],
      [-48.7893254, -26.223685],
      [-48.789388, -26.2238908],
      [-48.7894004, -26.224116],
      [-48.7893062, -26.2243362],
      [-48.789097, -26.2246079],
      [-48.7887297, -26.2249638],
      [-48.7885593, -26.2250666],
      [-48.7882977, -26.2251536]
    ],
    [
      [-48.8317076, -26.3365736],
      [-48.8316852, -26.3366747],
      [-48.831654, -26.3367487],
      [-48.8316186, -26.3367995],
      [-48.8315534, -26.3368779],
      [-48.8314853, -26.3369379],
      [-48.8314155, -26.3369993],
      [-48.8313017, -26.3370867]
    ],
    [
      [-48.8396686, -26.3092195],
      [-48.8395851, -26.3109615],
      [-48.8395802, -26.3110637]
    ],
    [
      [-48.8251078, -26.3390688],
      [-48.8250235, -26.3391407]
    ],
    [
      [-48.8250235, -26.3391407],
      [-48.824818, -26.3393121],
      [-48.8246427, -26.3394481]
    ],
    [
      [-48.8273912, -26.2735698],
      [-48.827307, -26.2735715],
      [-48.8272268, -26.2735768],
      [-48.8270789, -26.2735866],
      [-48.8268566, -26.2736068],
      [-48.8267816, -26.273605],
      [-48.8266901, -26.2735927],
      [-48.826605, -26.2735689],
      [-48.826555, -26.273533],
      [-48.8264912, -26.2734842]
    ],
    [
      [-48.8287884, -26.2724032],
      [-48.8293156, -26.2727459],
      [-48.8297432, -26.2730177],
      [-48.8298876, -26.2730994],
      [-48.830088, -26.273195]
    ],
    [
      [-48.8433029, -26.2855155],
      [-48.8433253, -26.2851898]
    ],
    [
      [-48.8099299, -26.2685864],
      [-48.8098661, -26.2684963]
    ],
    [
      [-48.8098661, -26.2684963],
      [-48.8096605, -26.2682056],
      [-48.8092519, -26.2676258]
    ],
    [
      [-48.8424349, -26.2955986],
      [-48.8424447, -26.2956053],
      [-48.8424899, -26.2956118],
      [-48.8425292, -26.2955948],
      [-48.8427537, -26.2953623],
      [-48.8428105, -26.2952823],
      [-48.8428451, -26.2952296]
    ],
    [
      [-48.8422603, -26.2954819],
      [-48.8424349, -26.2955986]
    ],
    [
      [-48.8432062, -26.28559],
      [-48.8432317, -26.2852989]
    ],
    [
      [-48.8433137, -26.2847354],
      [-48.8433706, -26.2846335],
      [-48.8434294, -26.2845354],
      [-48.8434864, -26.2844374],
      [-48.8434958, -26.284393],
      [-48.843506, -26.284342],
      [-48.8435181, -26.2841562],
      [-48.8435501, -26.2836654],
      [-48.8435599, -26.2835149],
      [-48.8435468, -26.2834548],
      [-48.8435089, -26.2834195],
      [-48.8434696, -26.283396],
      [-48.8433909, -26.2833777],
      [-48.8432583, -26.2833711],
      [-48.8432349, -26.283362],
      [-48.8432247, -26.2833502],
      [-48.8432197, -26.2833327],
      [-48.8432215, -26.2833105]
    ],
    [
      [-48.8610928, -26.2497115],
      [-48.8611513, -26.2493996],
      [-48.861197, -26.2491899],
      [-48.8612626, -26.248952],
      [-48.8613358, -26.2487324],
      [-48.8614265, -26.2485104],
      [-48.8615556, -26.248251],
      [-48.8617336, -26.2479368],
      [-48.8620067, -26.2475202],
      [-48.8623396, -26.2470271]
    ],
    [
      [-48.872316, -26.2683668],
      [-48.8723199, -26.2682603],
      [-48.8723294, -26.2679985],
      [-48.8723461, -26.2675402],
      [-48.8723548, -26.2673001],
      [-48.8723561, -26.2672654],
      [-48.8723783, -26.2666557],
      [-48.8724085, -26.2658282],
      [-48.8724157, -26.2656301],
      [-48.8724257, -26.2653547]
    ],
    [
      [-48.8834133, -26.3584016],
      [-48.8831761, -26.3582455],
      [-48.882934, -26.3580893],
      [-48.8827697, -26.3579809],
      [-48.8827136, -26.3579292],
      [-48.8825118, -26.3577485],
      [-48.8823353, -26.3575594],
      [-48.8821934, -26.3573134],
      [-48.8821063, -26.3571023],
      [-48.8819845, -26.3565406],
      [-48.8820102, -26.3565328],
      [-48.8822388, -26.3564549]
    ],
    [
      [-48.9052696, -26.373561],
      [-48.9051461, -26.3734107],
      [-48.9046557, -26.3728408],
      [-48.9043445, -26.3724768],
      [-48.9039382, -26.3720056],
      [-48.9038676, -26.3719437],
      [-48.9037466, -26.3718262],
      [-48.9035117, -26.3716558],
      [-48.9030161, -26.3713279],
      [-48.9020551, -26.3706967],
      [-48.9001561, -26.3694419],
      [-48.8963447, -26.3669339],
      [-48.8888116, -26.3619608],
      [-48.8885514, -26.3617922],
      [-48.8882466, -26.3615934],
      [-48.8877013, -26.3612313],
      [-48.8865882, -26.3604954],
      [-48.8843695, -26.359031],
      [-48.8836719, -26.3585699]
    ],
    [
      [-48.8836719, -26.3585699],
      [-48.8834133, -26.3584016]
    ],
    [
      [-48.9055297, -26.3738744],
      [-48.9052696, -26.373561]
    ],
    [
      [-48.8486691, -26.2745221],
      [-48.8487187, -26.2744374],
      [-48.8487486, -26.2743696],
      [-48.8487659, -26.274298],
      [-48.8487728, -26.2742292],
      [-48.8488007, -26.2736381],
      [-48.8488096, -26.2734703],
      [-48.8488225, -26.2733761]
    ],
    [
      [-48.8328233, -26.3485566],
      [-48.8328268, -26.3490785],
      [-48.8328264, -26.3491229]
    ],
    [
      [-48.8447107, -26.2647652],
      [-48.8446516, -26.2644057],
      [-48.8446472, -26.2642829],
      [-48.8446603, -26.2641849],
      [-48.8446938, -26.2640895],
      [-48.8447474, -26.2639744],
      [-48.8450881, -26.2632773],
      [-48.8452597, -26.2629209],
      [-48.8453136, -26.2627813],
      [-48.8453549, -26.2626437],
      [-48.8453807, -26.262522],
      [-48.8453965, -26.2623821],
      [-48.8454072, -26.2621704],
      [-48.8453911, -26.2619491],
      [-48.845367, -26.2617422],
      [-48.8453321, -26.2613502],
      [-48.8453339, -26.2612705],
      [-48.8453425, -26.2611858],
      [-48.8453619, -26.2611053],
      [-48.8453912, -26.2610134],
      [-48.8454244, -26.2609362],
      [-48.8454691, -26.2608496],
      [-48.8455231, -26.2607691],
      [-48.8455949, -26.2606791],
      [-48.8459027, -26.2603225],
      [-48.8466804, -26.2594342],
      [-48.8469173, -26.2591613],
      [-48.847164, -26.258863],
      [-48.8472027, -26.2588041],
      [-48.8472278, -26.2587473],
      [-48.8472379, -26.2586945],
      [-48.8472445, -26.2586128],
      [-48.8472579, -26.2579994],
      [-48.8472713, -26.2575496],
      [-48.8472767, -26.2574294],
      [-48.8472901, -26.2572032],
      [-48.8473169, -26.2567005],
      [-48.8473278, -26.256586],
      [-48.8473433, -26.2565049]
    ],
    [
      [-48.8078518, -26.362211],
      [-48.8076757, -26.3622238],
      [-48.8070999, -26.3622705]
    ],
    [
      [-48.813088, -26.3399563],
      [-48.8129299, -26.3398991]
    ],
    [
      [-48.8129299, -26.3398991],
      [-48.8128831, -26.3398827]
    ],
    [
      [-48.8190014, -26.3337964],
      [-48.8187287, -26.3338546]
    ],
    [
      [-48.8400571, -26.3241374],
      [-48.8399453, -26.3241892],
      [-48.8398353, -26.3242454],
      [-48.8397506, -26.324299],
      [-48.8396631, -26.3243648],
      [-48.8395699, -26.3244452],
      [-48.8394897, -26.3245232],
      [-48.8394224, -26.3245948],
      [-48.8392075, -26.32487],
      [-48.8390412, -26.3250825],
      [-48.8388671, -26.3253093],
      [-48.8387721, -26.3254283],
      [-48.8385196, -26.325758],
      [-48.8384729, -26.3258177],
      [-48.8383036, -26.3260435],
      [-48.8382455, -26.3261222],
      [-48.8381896, -26.3261904],
      [-48.8380973, -26.3263162],
      [-48.8380259, -26.3264286],
      [-48.8379567, -26.3265595],
      [-48.8378836, -26.3267279],
      [-48.8378517, -26.3268661],
      [-48.8378319, -26.3269912],
      [-48.8378025, -26.3272359],
      [-48.8377875, -26.32736],
      [-48.8377689, -26.3275721],
      [-48.8377599, -26.3277594],
      [-48.8377518, -26.3281921],
      [-48.8377532, -26.3283361],
      [-48.8377614, -26.32856],
      [-48.8377648, -26.3286246],
      [-48.837795, -26.3291901],
      [-48.8378013, -26.3293207],
      [-48.837815, -26.3295507],
      [-48.8378176, -26.329639],
      [-48.8378052, -26.3297491],
      [-48.8377739, -26.3299008],
      [-48.8377138, -26.3301114],
      [-48.8376596, -26.3302768],
      [-48.8376126, -26.3304266],
      [-48.8374172, -26.3310234],
      [-48.8373322, -26.3312173],
      [-48.8372465, -26.3313875],
      [-48.8371418, -26.3315834],
      [-48.8367573, -26.332303],
      [-48.8366468, -26.3324914],
      [-48.8365438, -26.3326568],
      [-48.8364286, -26.3328259],
      [-48.8363499, -26.3329208],
      [-48.8362705, -26.3330035],
      [-48.836144, -26.3330954],
      [-48.8359126, -26.3332091],
      [-48.835733, -26.3332931],
      [-48.8356074, -26.3333557],
      [-48.8348079, -26.3337398],
      [-48.8344403, -26.3339109],
      [-48.8343758, -26.3339401],
      [-48.8340054, -26.3340537],
      [-48.8338328, -26.3340959],
      [-48.8335206, -26.3341339],
      [-48.8330255, -26.3341844],
      [-48.8318581, -26.3343009],
      [-48.8317433, -26.3343105]
    ],
    [
      [-48.7913796, -26.2850733],
      [-48.788312, -26.2850242]
    ],
    [
      [-48.7916753, -26.285078],
      [-48.7913796, -26.2850733]
    ],
    [
      [-48.8946015, -26.2251484],
      [-48.8946621, -26.225171]
    ],
    [
      [-48.8946621, -26.225171],
      [-48.8947377, -26.2251976]
    ],
    [
      [-48.8707336, -26.2267836],
      [-48.8708058, -26.2267057]
    ],
    [
      [-48.8708058, -26.2267057],
      [-48.8718578, -26.225527],
      [-48.8719775, -26.2254447],
      [-48.8721443, -26.2253711],
      [-48.8746655, -26.2245241],
      [-48.8749388, -26.224434],
      [-48.8755643, -26.2242277],
      [-48.8764525, -26.2239348],
      [-48.8767973, -26.2238193],
      [-48.877052, -26.2237447],
      [-48.8774704, -26.2236557],
      [-48.8777758, -26.2236082],
      [-48.8779907, -26.2235955],
      [-48.878166, -26.2236075],
      [-48.8786132, -26.2236773],
      [-48.8787794, -26.2236917],
      [-48.8789456, -26.2236773],
      [-48.8790898, -26.2236439],
      [-48.8791957, -26.2236037],
      [-48.8798722, -26.2232907],
      [-48.881111, -26.2227304],
      [-48.8812245, -26.222679],
      [-48.882808, -26.2219629],
      [-48.8829698, -26.2218897]
    ],
    [
      [-48.904153, -26.1486324],
      [-48.9039022, -26.1484567]
    ],
    [
      [-48.9039022, -26.1484567],
      [-48.9037568, -26.1483544],
      [-48.9036698, -26.1482901],
      [-48.9035985, -26.1482249],
      [-48.9035595, -26.1481676],
      [-48.9035228, -26.1480962],
      [-48.9034892, -26.1480209],
      [-48.9034668, -26.1479155],
      [-48.9034582, -26.1478195],
      [-48.9034553, -26.1476747],
      [-48.9034976, -26.1462754],
      [-48.9035033, -26.1460462],
      [-48.9035049, -26.1459807],
      [-48.903509, -26.1457775],
      [-48.9035118, -26.1456187],
      [-48.9035029, -26.1454115],
      [-48.9034894, -26.1452797],
      [-48.9034662, -26.1451545],
      [-48.9032155, -26.1441093],
      [-48.9030326, -26.1433278],
      [-48.9029827, -26.1431768],
      [-48.9029195, -26.1430388],
      [-48.9028238, -26.1428536],
      [-48.9027965, -26.1428071],
      [-48.9026088, -26.1425005],
      [-48.9023465, -26.1420722],
      [-48.9022234, -26.1418708],
      [-48.9021759, -26.1417929],
      [-48.9021147, -26.1416927],
      [-48.9020053, -26.1415137],
      [-48.9018615, -26.1412784]
    ],
    [
      [-48.8491078, -26.2730704],
      [-48.8493518, -26.2728625],
      [-48.8494212, -26.2728184],
      [-48.8494872, -26.272788],
      [-48.8495702, -26.2727586],
      [-48.8496566, -26.2727335],
      [-48.8497076, -26.2727206]
    ],
    [
      [-48.846459, -26.2708409],
      [-48.8460722, -26.2706389],
      [-48.8456715, -26.2704297],
      [-48.845639, -26.2704127]
    ],
    [
      [-48.845639, -26.2704127],
      [-48.8455491, -26.2698658]
    ],
    [
      [-48.8155685, -26.2837463],
      [-48.8155044, -26.283739],
      [-48.8154511, -26.283723],
      [-48.8154119, -26.2836994],
      [-48.8147733, -26.2831927],
      [-48.8143819, -26.2828822],
      [-48.8142282, -26.2827602],
      [-48.8137376, -26.282371],
      [-48.8136296, -26.2823145],
      [-48.8134733, -26.2822533]
    ],
    [
      [-48.8425072, -26.3317293],
      [-48.8427388, -26.3330173]
    ],
    [
      [-48.8526335, -26.2519855],
      [-48.852705, -26.2519869]
    ],
    [
      [-48.9071579, -26.1653133],
      [-48.9072392, -26.1613429]
    ],
    [
      [-48.8829698, -26.2218897],
      [-48.8836638, -26.2215601],
      [-48.8838874, -26.2215095],
      [-48.8840468, -26.221506],
      [-48.8840977, -26.2215093],
      [-48.8842101, -26.2215165],
      [-48.8843811, -26.2215723],
      [-48.8860775, -26.2221682],
      [-48.8870352, -26.2225046],
      [-48.8943724, -26.2250684],
      [-48.8946015, -26.2251484]
    ],
    [
      [-48.8452935, -26.3190476],
      [-48.8474378, -26.3191516]
    ],
    [
      [-48.8378083, -26.3109899],
      [-48.8371407, -26.3109621],
      [-48.8359698, -26.3109134],
      [-48.8356535, -26.3109002]
    ],
    [
      [-48.8787057, -26.2912085],
      [-48.8787279, -26.2911228],
      [-48.8787326, -26.2909564],
      [-48.8787886, -26.2907251],
      [-48.8787968, -26.2905649],
      [-48.878784, -26.2903912],
      [-48.8787559, -26.290142],
      [-48.8787489, -26.2900552]
    ],
    [
      [-48.8917703, -26.3376572],
      [-48.8958221, -26.3374039],
      [-48.8974117, -26.337301],
      [-48.8982265, -26.3372496]
    ],
    [
      [-48.889367, -26.3378097],
      [-48.8898287, -26.3377798]
    ],
    [
      [-48.8361598, -26.287573],
      [-48.8355528, -26.2873545]
    ],
    [
      [-48.9053689, -26.2916538],
      [-48.9053531, -26.2919244]
    ],
    [
      [-48.884241, -26.3381652],
      [-48.889367, -26.3378097]
    ],
    [
      [-48.8879947, -26.2929268],
      [-48.8880953, -26.2927964],
      [-48.8881392, -26.2927411]
    ],
    [
      [-48.88776, -26.293207],
      [-48.8879947, -26.2929268]
    ],
    [
      [-48.8891105, -26.291977],
      [-48.889415, -26.2917798],
      [-48.8898674, -26.2915327],
      [-48.8901155, -26.2914007],
      [-48.8903626, -26.2912737],
      [-48.891863, -26.2905186]
    ],
    [
      [-48.8949428, -26.2920873],
      [-48.8947085, -26.2921083],
      [-48.89458, -26.2921122],
      [-48.8944635, -26.292108],
      [-48.894357, -26.2920955],
      [-48.8942517, -26.2920774],
      [-48.8941624, -26.2920535],
      [-48.8940773, -26.2920223],
      [-48.8939707, -26.2919687],
      [-48.8938593, -26.2918937],
      [-48.8926055, -26.2909201],
      [-48.8922457, -26.290624]
    ],
    [
      [-48.8445049, -26.2937561],
      [-48.8435768, -26.2938027],
      [-48.8433968, -26.2938099],
      [-48.8433799, -26.2933085],
      [-48.8434215, -26.2931533],
      [-48.8434892, -26.2931041]
    ],
    [
      [-48.8456836, -26.2940005],
      [-48.8459645, -26.2939778],
      [-48.8463291, -26.2939496]
    ],
    [
      [-48.8434892, -26.2931041],
      [-48.8435918, -26.293105],
      [-48.8438681, -26.2931202],
      [-48.8441571, -26.2930975],
      [-48.8442862, -26.2930691],
      [-48.8444695, -26.2930349],
      [-48.8444809, -26.2931011],
      [-48.8445049, -26.2937561]
    ],
    [
      [-48.844775, -26.2920225],
      [-48.843248, -26.292192]
    ],
    [
      [-48.827943, -26.2914379],
      [-48.8283068, -26.2915388]
    ],
    [
      [-48.8604324, -26.2978407],
      [-48.860325, -26.2978781]
    ],
    [
      [-48.8299031, -26.2747452],
      [-48.8291562, -26.2742973]
    ],
    [
      [-48.8724334, -26.2888027],
      [-48.8723868, -26.2878689],
      [-48.872386, -26.2878515],
      [-48.872357, -26.2872158],
      [-48.8723536, -26.2871192],
      [-48.8723449, -26.2869375],
      [-48.8723331, -26.2868745],
      [-48.8723091, -26.2868132],
      [-48.8722732, -26.2867574],
      [-48.8722142, -26.2866897],
      [-48.8721515, -26.2866391],
      [-48.8720761, -26.2865909],
      [-48.8719659, -26.2865353],
      [-48.8717894, -26.2864428],
      [-48.8716928, -26.2863782],
      [-48.8716369, -26.2863197],
      [-48.8715864, -26.286245],
      [-48.8715549, -26.2861752],
      [-48.8715302, -26.286061],
      [-48.8715278, -26.2859906],
      [-48.8715385, -26.2858993],
      [-48.8715576, -26.2858245],
      [-48.8718135, -26.2850261]
    ],
    [
      [-48.8750007, -26.2848106],
      [-48.8747245, -26.2848193],
      [-48.8741708, -26.2848135],
      [-48.8739226, -26.2848071],
      [-48.8738524, -26.2848057],
      [-48.8730314, -26.2847764],
      [-48.8729028, -26.284777],
      [-48.8728015, -26.2847816],
      [-48.872708, -26.2847909],
      [-48.8725523, -26.2848231],
      [-48.8724115, -26.2848552],
      [-48.8721677, -26.2849235],
      [-48.8718135, -26.2850261]
    ],
    [
      [-48.82835, -26.2738138],
      [-48.8282268, -26.2737477],
      [-48.8281152, -26.2736962],
      [-48.8279969, -26.2736546]
    ],
    [
      [-48.8451502, -26.2674388],
      [-48.8449809, -26.2664092],
      [-48.8449666, -26.2663221]
    ],
    [
      [-48.828486, -26.2722142],
      [-48.8286192, -26.2722974],
      [-48.8286695, -26.2723289],
      [-48.8287884, -26.2724032]
    ],
    [
      [-48.8060519, -26.3229151],
      [-48.8076204, -26.3226792],
      [-48.8081645, -26.3225973],
      [-48.8088716, -26.322495],
      [-48.8089538, -26.3224714]
    ],
    [
      [-48.8039794, -26.3186093],
      [-48.8042372, -26.3190153],
      [-48.8044964, -26.3194237],
      [-48.8047596, -26.3198382],
      [-48.8050147, -26.32024],
      [-48.805277, -26.3206533],
      [-48.8055373, -26.3210632],
      [-48.8056331, -26.3212142],
      [-48.8057033, -26.3213328],
      [-48.8057428, -26.3214234],
      [-48.8057736, -26.3215175],
      [-48.8058188, -26.3216962],
      [-48.8058833, -26.3219938],
      [-48.8059691, -26.3224626],
      [-48.8060519, -26.3229151]
    ],
    [
      [-48.7969064, -26.3169544],
      [-48.7969546, -26.3168273],
      [-48.7970095, -26.3166959],
      [-48.7971778, -26.3163679],
      [-48.7973109, -26.3161033],
      [-48.7973589, -26.3159935],
      [-48.7974014, -26.3158959],
      [-48.7974225, -26.3158245],
      [-48.7974374, -26.3157673],
      [-48.7974397, -26.3156912],
      [-48.7974183, -26.3156214],
      [-48.7973854, -26.3155477],
      [-48.7971498, -26.3151122]
    ],
    [
      [-48.8142607, -26.3207831],
      [-48.816065, -26.3202295]
    ],
    [
      [-48.8279426, -26.2718763],
      [-48.8283509, -26.2721297],
      [-48.828486, -26.2722142]
    ],
    [
      [-48.8268265, -26.271174],
      [-48.8271292, -26.2713681],
      [-48.8272303, -26.271431]
    ],
    [
      [-48.8190554, -26.2637368],
      [-48.817518, -26.2616332]
    ],
    [
      [-48.8295176, -26.3100144],
      [-48.829419, -26.3099388],
      [-48.82926, -26.3098169],
      [-48.8288877, -26.3095314],
      [-48.8285526, -26.3092745],
      [-48.8284267, -26.309178],
      [-48.8281126, -26.3089371],
      [-48.8277892, -26.3086892],
      [-48.8275916, -26.3085376]
    ],
    [
      [-48.8197563, -26.2708614],
      [-48.8202568, -26.2709731],
      [-48.8209271, -26.2711287],
      [-48.8221032, -26.2713972]
    ],
    [
      [-48.8258017, -26.2729529],
      [-48.8257097, -26.2728796],
      [-48.8252983, -26.2725463],
      [-48.8242152, -26.2716249]
    ],
    [
      [-48.8398221, -26.2790378],
      [-48.8399134, -26.2790952],
      [-48.8412874, -26.2799589],
      [-48.8437899, -26.2815342]
    ],
    [
      [-48.8341171, -26.280551],
      [-48.8338284, -26.2796607],
      [-48.833703, -26.2792888],
      [-48.8336338, -26.2791083],
      [-48.833555, -26.2789394],
      [-48.8334728, -26.2787903],
      [-48.8334034, -26.2786899],
      [-48.833336, -26.2785992],
      [-48.8329603, -26.2781285],
      [-48.8329041, -26.2780518],
      [-48.8328495, -26.2779715],
      [-48.8327983, -26.2778883],
      [-48.83275, -26.2777807]
    ],
    [
      [-48.8397307, -26.2740868],
      [-48.8395498, -26.2742515],
      [-48.8391405, -26.2746377],
      [-48.8384516, -26.2752991],
      [-48.8383443, -26.2754021],
      [-48.8382286, -26.2755166],
      [-48.8375033, -26.2762032],
      [-48.8370633, -26.2765965],
      [-48.8367024, -26.2768899],
      [-48.8365672, -26.276987],
      [-48.8364985, -26.2770293],
      [-48.8364279, -26.277062],
      [-48.836372, -26.2770836],
      [-48.8362981, -26.277108],
      [-48.8361119, -26.2771631],
      [-48.8351253, -26.2774575]
    ],
    [
      [-48.8382026, -26.2813384],
      [-48.8387382, -26.2805776],
      [-48.8389843, -26.2802279],
      [-48.8391102, -26.280049],
      [-48.8392376, -26.2798681],
      [-48.8393878, -26.2796547],
      [-48.8398221, -26.2790378]
    ],
    [
      [-48.8184352, -26.2705644],
      [-48.8186014, -26.2705989],
      [-48.8187697, -26.2706344],
      [-48.819303, -26.2707555],
      [-48.8197563, -26.2708614]
    ],
    [
      [-48.834534, -26.281811],
      [-48.8343259, -26.2811816],
      [-48.8341171, -26.280551]
    ],
    [
      [-48.8422568, -26.3240875],
      [-48.8422693, -26.3238352],
      [-48.8422891, -26.3234367],
      [-48.8422993, -26.3232316]
    ],
    [
      [-48.8473433, -26.2565049],
      [-48.8473808, -26.2564219],
      [-48.8474462, -26.2563229],
      [-48.8475261, -26.256217],
      [-48.8478453, -26.2558875],
      [-48.8481136, -26.2556089],
      [-48.8484622, -26.2552717],
      [-48.8486394, -26.2550845],
      [-48.848811, -26.2548824],
      [-48.8489995, -26.254625],
      [-48.8492917, -26.254226],
      [-48.8494279, -26.2540405]
    ],
    [
      [-48.8030577, -26.2781016],
      [-48.802503, -26.2776972]
    ],
    [
      [-48.8119536, -26.2821715],
      [-48.8115352, -26.2826519]
    ],
    [
      [-49.0174423, -26.1331096],
      [-49.0174274, -26.1331183]
    ],
    [
      [-49.0177965, -26.1328551],
      [-49.017706, -26.1329532],
      [-49.0176309, -26.1330056],
      [-49.0174423, -26.1331096]
    ],
    [
      [-49.0174274, -26.1331183],
      [-49.0174063, -26.1331311],
      [-49.0173164, -26.1331338],
      [-49.0172809, -26.1331001],
      [-49.0171937, -26.1330682],
      [-49.0170284, -26.1330751],
      [-49.0169594, -26.133011],
      [-49.0168913, -26.1329999],
      [-49.0167988, -26.1330321],
      [-49.016659, -26.1330264],
      [-49.0165855, -26.133005],
      [-49.0163998, -26.133014],
      [-49.0162214, -26.1330417],
      [-49.0161819, -26.1330676],
      [-49.0160323, -26.1330718],
      [-49.015915, -26.1331031],
      [-49.0158587, -26.1331712]
    ],
    [
      [-48.8357794, -26.2952466],
      [-48.8354636, -26.2952009],
      [-48.835245, -26.2950855],
      [-48.8350807, -26.2949268],
      [-48.8350639, -26.2946503],
      [-48.8351625, -26.2944333],
      [-48.8353633, -26.2942337],
      [-48.8356151, -26.2940726],
      [-48.8357851, -26.2939673],
      [-48.8360929, -26.2940798],
      [-48.8363933, -26.2942481],
      [-48.8366816, -26.2944224],
      [-48.8367415, -26.2944647],
      [-48.8367829, -26.294521],
      [-48.8366977, -26.2946942],
      [-48.8365428, -26.2949551],
      [-48.8364711, -26.2950747],
      [-48.8362377, -26.2951288],
      [-48.8360365, -26.2951919],
      [-48.8357794, -26.2952466]
    ],
    [
      [-48.8478455, -26.2935722],
      [-48.8478567, -26.2937887]
    ],
    [
      [-48.8431805, -26.2874614],
      [-48.8431763, -26.2873322],
      [-48.843175, -26.28717],
      [-48.8431792, -26.2870416],
      [-48.8431873, -26.2869093],
      [-48.8433029, -26.2855155]
    ],
    [
      [-48.8431805, -26.2874614],
      [-48.843086, -26.2874658]
    ],
    [
      [-48.8429635, -26.2952018],
      [-48.843, -26.2951223],
      [-48.8430227, -26.2950622],
      [-48.84304, -26.294997],
      [-48.8430553, -26.2949117],
      [-48.8430647, -26.2948189],
      [-48.8431044, -26.2937922],
      [-48.843116, -26.2934459],
      [-48.8431273, -26.2931267],
      [-48.8431434, -26.292713],
      [-48.8431451, -26.2926308],
      [-48.8431518, -26.2921149]
    ],
    [
      [-48.8431334, -26.3438541],
      [-48.8431803, -26.3430778]
    ],
    [
      [-48.8317753, -26.3111904],
      [-48.8316313, -26.311146],
      [-48.8309312, -26.3109164],
      [-48.8306043, -26.3108093],
      [-48.8305217, -26.3107733],
      [-48.8304722, -26.3107447],
      [-48.8304338, -26.3107169]
    ],
    [
      [-48.8431665, -26.2951443],
      [-48.8433717, -26.2951309]
    ],
    [
      [-48.8628543, -26.3130458],
      [-48.8625933, -26.313254]
    ],
    [
      [-48.8645209, -26.2919411],
      [-48.8643858, -26.2898515],
      [-48.8643214, -26.2888555],
      [-48.8641168, -26.2856912],
      [-48.8640462, -26.2845989]
    ],
    [
      [-48.8645741, -26.2927644],
      [-48.8638316, -26.2928118],
      [-48.8636433, -26.2928238],
      [-48.8626771, -26.2928855],
      [-48.861753, -26.2929444],
      [-48.8609051, -26.2929985],
      [-48.8600614, -26.2930523],
      [-48.8590277, -26.2931183],
      [-48.8583025, -26.2931645],
      [-48.8582511, -26.2931678],
      [-48.85762, -26.2932081],
      [-48.8568154, -26.2932594],
      [-48.8560473, -26.2933084],
      [-48.8553646, -26.2933519],
      [-48.8539583, -26.2934416],
      [-48.8526111, -26.2935276],
      [-48.8501371, -26.2936854]
    ],
    [
      [-48.7988731, -26.2195644],
      [-48.798811, -26.2195512],
      [-48.798719, -26.2194985]
    ],
    [
      [-48.8030788, -26.3174477],
      [-48.8028267, -26.3170486],
      [-48.8021475, -26.3159736],
      [-48.8020645, -26.3158421]
    ],
    [
      [-48.8020645, -26.3158421],
      [-48.8018704, -26.3155349]
    ],
    [
      [-48.8304784, -26.3257636],
      [-48.8301326, -26.3255068]
    ],
    [
      [-48.8132713, -26.2907997],
      [-48.813417, -26.2909341]
    ],
    [
      [-48.8079675, -26.266111],
      [-48.8072067, -26.2655649],
      [-48.8060704, -26.2646658],
      [-48.8049233, -26.2637682],
      [-48.8042397, -26.263212]
    ],
    [
      [-48.8312674, -26.3381866],
      [-48.8313203, -26.3383343],
      [-48.8313631, -26.3384845],
      [-48.8314057, -26.3387148],
      [-48.831424, -26.3388433],
      [-48.8314355, -26.3389711],
      [-48.8314374, -26.3391104],
      [-48.8314167, -26.3392761],
      [-48.8313831, -26.3394454],
      [-48.8313455, -26.3395819],
      [-48.8313189, -26.3396699],
      [-48.8312135, -26.3400171],
      [-48.8310755, -26.3404914],
      [-48.8310591, -26.3405585],
      [-48.8310447, -26.3406176],
      [-48.8310354, -26.3407063],
      [-48.8310295, -26.3407619],
      [-48.8310398, -26.3408645],
      [-48.8311282, -26.3415234],
      [-48.8311429, -26.3416078],
      [-48.8311566, -26.3416619],
      [-48.8311756, -26.3417015],
      [-48.8313855, -26.3420308],
      [-48.8314083, -26.3420658],
      [-48.8314282, -26.3420965],
      [-48.8314588, -26.3421372],
      [-48.8315614, -26.34226]
    ],
    [
      [-48.8625933, -26.313254],
      [-48.8625173, -26.3133134],
      [-48.8624618, -26.3133579],
      [-48.8624101, -26.3134026],
      [-48.8620859, -26.3137036],
      [-48.8619967, -26.3137894],
      [-48.8614982, -26.3142983]
    ],
    [
      [-48.8184729, -26.2180225],
      [-48.8185288, -26.2179875],
      [-48.8186205, -26.2179301]
    ],
    [
      [-48.8597732, -26.3134361],
      [-48.8596893, -26.3134256],
      [-48.8592566, -26.3133899],
      [-48.8591887, -26.313381],
      [-48.8591114, -26.3133675],
      [-48.8590339, -26.3133494],
      [-48.8589686, -26.3133287],
      [-48.8589036, -26.3133056],
      [-48.8588445, -26.3132811],
      [-48.8587847, -26.3132518],
      [-48.85872, -26.3132143],
      [-48.8586498, -26.3131692],
      [-48.8584659, -26.3130375]
    ],
    [
      [-48.8598808, -26.3134548],
      [-48.8597732, -26.3134361]
    ],
    [
      [-48.8600606, -26.3135011],
      [-48.8599836, -26.3134786],
      [-48.8598808, -26.3134548]
    ],
    [
      [-48.8307966, -26.3156404],
      [-48.8306503, -26.3155509],
      [-48.8303719, -26.3155588],
      [-48.8302262, -26.3155905],
      [-48.8300804, -26.315642],
      [-48.8299213, -26.315741],
      [-48.829802, -26.3158598],
      [-48.8295667, -26.3161161],
      [-48.8294582, -26.3161884],
      [-48.8293232, -26.3162619],
      [-48.8290509, -26.3163231],
      [-48.828786, -26.316289],
      [-48.828526, -26.3161748]
    ],
    [
      [-48.9168057, -26.2778748],
      [-48.916707, -26.2779371]
    ],
    [
      [-48.9170191, -26.2778847],
      [-48.9168057, -26.2778748]
    ],
    [
      [-48.9233561, -26.278293],
      [-48.923357, -26.2782211],
      [-48.9229795, -26.2781808],
      [-48.9225551, -26.2781285],
      [-48.9213334, -26.2780863],
      [-48.9200351, -26.2780287],
      [-48.918993, -26.2779854],
      [-48.9188616, -26.2779566],
      [-48.9185934, -26.2779481],
      [-48.9184821, -26.277953],
      [-48.9170191, -26.2778847]
    ],
    [
      [-48.814116, -26.3617981],
      [-48.8136532, -26.3618286],
      [-48.8132475, -26.3618553],
      [-48.8127285, -26.3618896],
      [-48.8125521, -26.3619012],
      [-48.8123544, -26.3619142],
      [-48.8121015, -26.3619309]
    ],
    [
      [-48.8164862, -26.3405074],
      [-48.8164505, -26.3408441],
      [-48.8164398, -26.3409519],
      [-48.8163956, -26.3414886],
      [-48.8164014, -26.3415816],
      [-48.8164121, -26.3416615],
      [-48.8164449, -26.3417791],
      [-48.8165004, -26.3419206],
      [-48.8165767, -26.3420663],
      [-48.8172145, -26.3431414],
      [-48.8172567, -26.3432264],
      [-48.8173098, -26.3433431],
      [-48.8173463, -26.3434346]
    ],
    [
      [-48.8612717, -26.2852166],
      [-48.8606924, -26.2849574],
      [-48.8603458, -26.2848329],
      [-48.8601885, -26.2847877],
      [-48.8600633, -26.2847586],
      [-48.8598938, -26.2847292],
      [-48.8597194, -26.2847027],
      [-48.859418, -26.2846722],
      [-48.8590917, -26.2846477],
      [-48.8585982, -26.2846219],
      [-48.8573565, -26.2845684],
      [-48.856364, -26.2845334],
      [-48.8550455, -26.2844754],
      [-48.8540228, -26.2844271],
      [-48.8530997, -26.2843851],
      [-48.8526556, -26.284365],
      [-48.8524054, -26.2843536],
      [-48.8519315, -26.2843321],
      [-48.8512793, -26.2843024],
      [-48.8502287, -26.2842547],
      [-48.8501079, -26.2842493]
    ],
    [
      [-48.8753903, -26.2795831],
      [-48.8755252, -26.2802431],
      [-48.875539, -26.2803219],
      [-48.875548, -26.2804052],
      [-48.8758129, -26.284075]
    ],
    [
      [-48.8310856, -26.3012094],
      [-48.8311654, -26.3012596],
      [-48.8315328, -26.3014909],
      [-48.8316681, -26.3015826],
      [-48.8317673, -26.3016617],
      [-48.8318886, -26.3017797],
      [-48.8321062, -26.30205]
    ],
    [
      [-48.847142, -26.3529628],
      [-48.8470151, -26.353166],
      [-48.8468958, -26.3533494],
      [-48.8468352, -26.3534489],
      [-48.8467748, -26.353569],
      [-48.8467173, -26.353685],
      [-48.8466812, -26.3537676],
      [-48.8466604, -26.3538262],
      [-48.8466338, -26.3539032],
      [-48.8466197, -26.3539646],
      [-48.8466074, -26.354032],
      [-48.8464654, -26.3550125],
      [-48.8464119, -26.3553822],
      [-48.8463636, -26.3556866],
      [-48.8463115, -26.3559917],
      [-48.8462786, -26.356195]
    ],
    [
      [-48.8497076, -26.2727206],
      [-48.8498752, -26.2726858],
      [-48.8499554, -26.2726689]
    ],
    [
      [-48.8478455, -26.2935722],
      [-48.8475967, -26.2935957]
    ],
    [
      [-48.8475967, -26.2935957],
      [-48.846902, -26.2936418],
      [-48.8469128, -26.2939039],
      [-48.8463291, -26.2939496]
    ],
    [
      [-48.8459323, -26.2811425],
      [-48.846009, -26.2810037],
      [-48.8460515, -26.2809403],
      [-48.8460833, -26.2809149],
      [-48.8461187, -26.2809054],
      [-48.8461541, -26.2809085],
      [-48.8461895, -26.2809244],
      [-48.8462143, -26.280953],
      [-48.8462178, -26.280991],
      [-48.8462001, -26.2810545],
      [-48.8461457, -26.2812243]
    ],
    [
      [-48.8335414, -26.3067348],
      [-48.8348875, -26.3070004],
      [-48.8353036, -26.3070862]
    ],
    [
      [-48.8304338, -26.3107169],
      [-48.8302727, -26.3105934],
      [-48.8301981, -26.3105362],
      [-48.8297614, -26.3102002]
    ],
    [
      [-48.8020869, -26.2242454],
      [-48.8022928, -26.2240981]
    ],
    [
      [-48.8017483, -26.2252524],
      [-48.8015585, -26.2251772],
      [-48.8014211, -26.2250798]
    ],
    [
      [-48.8018911, -26.2252716],
      [-48.8017483, -26.2252524]
    ],
    [
      [-48.8022633, -26.2251965],
      [-48.8020641, -26.2252536],
      [-48.8018911, -26.2252716]
    ],
    [
      [-48.8022928, -26.2240981],
      [-48.8023666, -26.2241005],
      [-48.8024497, -26.2241305],
      [-48.8025349, -26.2241991]
    ],
    [
      [-48.8614982, -26.3142983],
      [-48.8614629, -26.3143981],
      [-48.8614495, -26.314457],
      [-48.8614414, -26.3145255],
      [-48.8614393, -26.314598]
    ],
    [
      [-48.8614393, -26.314598],
      [-48.8613238, -26.3144764]
    ],
    [
      [-48.8178089, -26.2959199],
      [-48.8174615, -26.2955758],
      [-48.8172968, -26.2954127],
      [-48.8169992, -26.2951179],
      [-48.8169285, -26.2950597],
      [-48.8168581, -26.2950116],
      [-48.8167917, -26.29497],
      [-48.8166102, -26.2948723],
      [-48.8162217, -26.2946652]
    ],
    [
      [-48.8443351, -26.2628795],
      [-48.8448426, -26.2628717],
      [-48.8449065, -26.2628562],
      [-48.8452597, -26.2629209]
    ],
    [
      [-48.786236, -26.2852238],
      [-48.78418, -26.2862976],
      [-48.7837552, -26.2865194]
    ],
    [
      [-48.8418398, -26.3324879],
      [-48.8418778, -26.3317212],
      [-48.8419199, -26.3308734],
      [-48.8419302, -26.3306657],
      [-48.841936, -26.3305493],
      [-48.8419625, -26.3300154],
      [-48.8420082, -26.3290951],
      [-48.8420319, -26.3286178],
      [-48.8420431, -26.328391],
      [-48.8420867, -26.3275139],
      [-48.8420913, -26.3274211],
      [-48.8421361, -26.3265195],
      [-48.8421402, -26.3264366],
      [-48.8421448, -26.3263434],
      [-48.8421581, -26.3260749],
      [-48.842181, -26.3256145],
      [-48.842184, -26.3255532],
      [-48.8422361, -26.3245045]
    ],
    [
      [-48.8418355, -26.3325739],
      [-48.8418398, -26.3324879]
    ],
    [
      [-48.860325, -26.2978781],
      [-48.8602343, -26.2979085],
      [-48.8599301, -26.2980105]
    ],
    [
      [-48.8845377, -26.2962239],
      [-48.8846011, -26.296208],
      [-48.8846675, -26.2961906],
      [-48.8847345, -26.2961653],
      [-48.8848277, -26.2961279],
      [-48.8848791, -26.2960927],
      [-48.8849588, -26.2960192],
      [-48.8850588, -26.2958901]
    ],
    [
      [-48.8305607, -26.3258204],
      [-48.8304784, -26.3257636]
    ],
    [
      [-48.8219429, -26.2711999],
      [-48.819583, -26.2693251],
      [-48.8193473, -26.269138],
      [-48.8167964, -26.2671115],
      [-48.8142743, -26.2651079],
      [-48.8141807, -26.2650841]
    ],
    [
      [-48.8523947, -26.2525793],
      [-48.8524523, -26.2526023],
      [-48.8524967, -26.2526303],
      [-48.8525231, -26.2526599],
      [-48.8525165, -26.2527572],
      [-48.8525165, -26.2528225],
      [-48.852543, -26.2528521],
      [-48.8525757, -26.2528695]
    ],
    [
      [-48.8922457, -26.290624],
      [-48.8922144, -26.2905464],
      [-48.8922078, -26.2904665],
      [-48.8922192, -26.2904295]
    ],
    [
      [-48.9153762, -26.2919023],
      [-48.915303, -26.2919127],
      [-48.9152403, -26.2919256]
    ],
    [
      [-48.9152403, -26.2919256],
      [-48.9151356, -26.2919569],
      [-48.9148193, -26.2920555],
      [-48.9147367, -26.2920752],
      [-48.9146417, -26.2920905],
      [-48.9145674, -26.2920969],
      [-48.9144853, -26.2921017],
      [-48.9144011, -26.2921001],
      [-48.9143289, -26.2920971],
      [-48.9139423, -26.292078],
      [-48.9132958, -26.292046],
      [-48.9127137, -26.2920172],
      [-48.912089, -26.2919863],
      [-48.911482, -26.2919562],
      [-48.9109867, -26.2919317]
    ],
    [
      [-48.8961768, -26.2920673],
      [-48.895798, -26.2920503],
      [-48.8955864, -26.2920473],
      [-48.895411, -26.2920523],
      [-48.8951914, -26.2920682],
      [-48.8949428, -26.2920873]
    ],
    [
      [-48.8964031, -26.2920805],
      [-48.8961768, -26.2920673]
    ],
    [
      [-48.8967199, -26.288054],
      [-48.8969892, -26.2879154],
      [-48.8975315, -26.2876393],
      [-48.8977513, -26.2875348],
      [-48.8978625, -26.2874884],
      [-48.8979535, -26.2874541],
      [-48.8980484, -26.2874193],
      [-48.8981415, -26.287388],
      [-48.8982525, -26.2873535],
      [-48.8983665, -26.2873253],
      [-48.8984202, -26.287315],
      [-48.8984912, -26.2873014],
      [-48.8986794, -26.2872749]
    ],
    [
      [-48.8965474, -26.2881415],
      [-48.8967199, -26.288054]
    ],
    [
      [-48.9074732, -26.2072138],
      [-48.9074592, -26.2072128],
      [-48.9074645, -26.2071271]
    ],
    [
      [-48.9074592, -26.2072128],
      [-48.9073965, -26.207209]
    ],
    [
      [-48.9074645, -26.2071271],
      [-48.9074697, -26.2070682]
    ],
    [
      [-48.8664401, -26.2935935],
      [-48.8681413, -26.2934797]
    ],
    [
      [-48.8165458, -26.2828126],
      [-48.8157465, -26.283664],
      [-48.815693, -26.2837111],
      [-48.815629, -26.283736],
      [-48.8155685, -26.2837463]
    ],
    [
      [-48.8513443, -26.3091998],
      [-48.8509112, -26.3090236],
      [-48.8500012, -26.3086533]
    ],
    [
      [-48.8433717, -26.2951309],
      [-48.8434733, -26.2951242],
      [-48.8436143, -26.2951149],
      [-48.8443736, -26.2950649],
      [-48.8445522, -26.2950531],
      [-48.8456334, -26.2949819],
      [-48.8457515, -26.2949741],
      [-48.8458949, -26.2949647],
      [-48.8460801, -26.2949524],
      [-48.8462368, -26.2949421],
      [-48.8471062, -26.2948848],
      [-48.8472803, -26.2948734],
      [-48.8478586, -26.2948353],
      [-48.8479548, -26.2948289]
    ],
    [
      [-48.8398221, -26.2790378],
      [-48.8401297, -26.2786008],
      [-48.8407018, -26.2777881],
      [-48.8409291, -26.2774652]
    ],
    [
      [-48.8425784, -26.2751221],
      [-48.8418919, -26.2748808]
    ],
    [
      [-48.83275, -26.2777807],
      [-48.8325821, -26.277256],
      [-48.8324842, -26.2769209],
      [-48.8323425, -26.2764742],
      [-48.8323162, -26.2764049],
      [-48.8322775, -26.2763319],
      [-48.8322402, -26.2762807],
      [-48.832187, -26.2762193]
    ],
    [
      [-48.8370942, -26.280268],
      [-48.8372498, -26.2804867],
      [-48.8373371, -26.2805848],
      [-48.8374465, -26.2806837],
      [-48.8379414, -26.2811122],
      [-48.8382026, -26.2813384],
      [-48.8382866, -26.2814136],
      [-48.8391084, -26.2821493],
      [-48.8392896, -26.2822976]
    ],
    [
      [-48.8406456, -26.284029],
      [-48.8382023, -26.2831422]
    ],
    [
      [-48.8416452, -26.3018068],
      [-48.841595, -26.3018926],
      [-48.8415217, -26.3020196],
      [-48.8414892, -26.3020835],
      [-48.8414604, -26.3021584],
      [-48.8414476, -26.3022237],
      [-48.8414369, -26.3030107],
      [-48.841429, -26.3031504],
      [-48.8414134, -26.3032471],
      [-48.8413807, -26.3033531],
      [-48.8413367, -26.3034564],
      [-48.8412906, -26.3035423],
      [-48.8411569, -26.3037637],
      [-48.841107, -26.303861],
      [-48.8410736, -26.303945],
      [-48.8410458, -26.3040451],
      [-48.841029, -26.3041247],
      [-48.8410148, -26.3042115],
      [-48.8410075, -26.3043072],
      [-48.8410055, -26.3044548]
    ],
    [
      [-48.8258017, -26.2729529],
      [-48.8257019, -26.2730592],
      [-48.8250109, -26.2737952],
      [-48.8245149, -26.2743237]
    ],
    [
      [-48.8449666, -26.2663221],
      [-48.8448392, -26.2655471],
      [-48.8447107, -26.2647652]
    ],
    [
      [-48.8114651, -26.2743027],
      [-48.8115298, -26.2734476],
      [-48.811579, -26.2727721]
    ],
    [
      [-48.8056049, -26.2752882],
      [-48.8050233, -26.274892]
    ],
    [
      [-48.811579, -26.2727721],
      [-48.8116288, -26.2720892],
      [-48.8117016, -26.2710908]
    ],
    [
      [-48.8220219, -26.2769793],
      [-48.8215121, -26.2775225],
      [-48.820831, -26.278248],
      [-48.8202481, -26.2788689]
    ],
    [
      [-48.802719, -26.2733221],
      [-48.8021503, -26.2729345],
      [-48.8015768, -26.2725438]
    ],
    [
      [-48.8202481, -26.2788689],
      [-48.8199855, -26.2791485],
      [-48.8197592, -26.2793897],
      [-48.8192488, -26.2799334]
    ],
    [
      [-48.814401, -26.2927225],
      [-48.8136572, -26.2916641]
    ],
    [
      [-48.8266902, -26.3072617],
      [-48.8264775, -26.3069465],
      [-48.8263136, -26.3067036],
      [-48.8262397, -26.3065941]
    ],
    [
      [-48.8117016, -26.2710908],
      [-48.8123522, -26.2707516],
      [-48.8127814, -26.2705311],
      [-48.812933, -26.270452],
      [-48.8130382, -26.2704051],
      [-48.8131067, -26.2703778],
      [-48.8131799, -26.2703533],
      [-48.8132717, -26.2703234],
      [-48.8133439, -26.2703051],
      [-48.8134314, -26.2702861],
      [-48.8135351, -26.2702697],
      [-48.8136407, -26.2702608]
    ],
    [
      [-48.8105306, -26.2835488],
      [-48.8104496, -26.2834898],
      [-48.8099869, -26.2831525],
      [-48.8094907, -26.2827908],
      [-48.8089029, -26.2823624],
      [-48.8083485, -26.2819582],
      [-48.8080716, -26.2817564],
      [-48.8075661, -26.2813879]
    ],
    [
      [-48.8183379, -26.2964438],
      [-48.8178089, -26.2959199]
    ],
    [
      [-48.8200465, -26.2981361],
      [-48.8197047, -26.2977976],
      [-48.8192438, -26.2973411],
      [-48.8190608, -26.2971598],
      [-48.818979, -26.2970788],
      [-48.8183379, -26.2964438]
    ],
    [
      [-48.8083777, -26.2663997],
      [-48.8079675, -26.266111]
    ],
    [
      [-48.8682184, -26.2951901],
      [-48.8682589, -26.2960893]
    ],
    [
      [-48.9109867, -26.2919317],
      [-48.9105448, -26.2919099],
      [-48.910439, -26.2919047],
      [-48.9098172, -26.2918739]
    ],
    [
      [-48.9098172, -26.2918739],
      [-48.9091016, -26.2918385],
      [-48.9083847, -26.291803],
      [-48.9076772, -26.291768],
      [-48.9069669, -26.2917329],
      [-48.9061836, -26.2916941],
      [-48.9057457, -26.2916724]
    ],
    [
      [-48.8981904, -26.2921633],
      [-48.8964031, -26.2920805]
    ],
    [
      [-48.8881392, -26.2927411],
      [-48.8882375, -26.2925758],
      [-48.8883287, -26.2924675],
      [-48.8884266, -26.2923714],
      [-48.8885486, -26.292274],
      [-48.888963, -26.2920323],
      [-48.8891105, -26.291977]
    ],
    [
      [-48.8309609, -26.2735713],
      [-48.8310836, -26.2736221],
      [-48.8313794, -26.2737445],
      [-48.8317388, -26.2738984]
    ],
    [
      [-48.830088, -26.273195],
      [-48.8305718, -26.273409],
      [-48.8309609, -26.2735713]
    ],
    [
      [-48.8392896, -26.2822976],
      [-48.8393572, -26.282341],
      [-48.8394313, -26.2823851],
      [-48.8395189, -26.2824327],
      [-48.8400473, -26.2826886],
      [-48.8401118, -26.2827244]
    ],
    [
      [-48.8291562, -26.2742973],
      [-48.82835, -26.2738138]
    ],
    [
      [-48.8898287, -26.3377798],
      [-48.8917703, -26.3376572]
    ],
    [
      [-48.8525757, -26.2528695],
      [-48.8525998, -26.2528616],
      [-48.8526183, -26.252826],
      [-48.8526355, -26.2526659]
    ],
    [
      [-48.8375736, -26.2776307],
      [-48.8376724, -26.2776833],
      [-48.8397305, -26.2789801],
      [-48.8398221, -26.2790378]
    ],
    [
      [-48.8628777, -26.2833665],
      [-48.8628133, -26.2834286],
      [-48.8627679, -26.2834961],
      [-48.8627432, -26.2835689],
      [-48.8626846, -26.2838399],
      [-48.8626402, -26.2840054],
      [-48.8625859, -26.2841965],
      [-48.8624405, -26.284637]
    ],
    [
      [-48.8622935, -26.2848836],
      [-48.8621621, -26.2849758],
      [-48.8620074, -26.2850601]
    ],
    [
      [-48.8620074, -26.2850601],
      [-48.8617726, -26.2851879],
      [-48.8616495, -26.285233],
      [-48.861533, -26.2852555],
      [-48.8614584, -26.2852571],
      [-48.8613573, -26.2852403],
      [-48.8612717, -26.2852166]
    ],
    [
      [-48.8624405, -26.284637],
      [-48.8623837, -26.2847616],
      [-48.8622935, -26.2848836]
    ],
    [
      [-48.8725568, -26.2909165],
      [-48.872487, -26.2899233],
      [-48.8724709, -26.2896107],
      [-48.8724689, -26.2895674],
      [-48.8724637, -26.2894553],
      [-48.8724334, -26.2888027]
    ],
    [
      [-48.8718135, -26.2850261],
      [-48.8709863, -26.2852482]
    ],
    [
      [-48.8629924, -26.3129309],
      [-48.8628543, -26.3130458]
    ],
    [
      [-48.856541, -26.3118545],
      [-48.8564922, -26.3118044],
      [-48.8564382, -26.311741],
      [-48.8563858, -26.3116668],
      [-48.856283, -26.3115154],
      [-48.856166, -26.3113423]
    ],
    [
      [-48.8804223, -26.3383555],
      [-48.8821488, -26.3382968],
      [-48.884241, -26.3381652]
    ],
    [
      [-48.8483281, -26.2718167],
      [-48.847497, -26.2713828],
      [-48.846459, -26.2708409]
    ],
    [
      [-48.8489136, -26.2721224],
      [-48.8486227, -26.2719705],
      [-48.8483281, -26.2718167]
    ],
    [
      [-48.8496776, -26.2725213],
      [-48.8489136, -26.2721224]
    ],
    [
      [-48.8206899, -26.2501917],
      [-48.8210137, -26.2495354]
    ],
    [
      [-48.821211, -26.2468974],
      [-48.8211247, -26.2466547],
      [-48.8207696, -26.2456172],
      [-48.8206459, -26.2452558],
      [-48.8203886, -26.2445039],
      [-48.8201553, -26.2438404],
      [-48.8198854, -26.2430658]
    ],
    [
      [-48.818951, -26.2619754],
      [-48.8189766, -26.2624787]
    ],
    [
      [-48.8200112, -26.251113],
      [-48.820039, -26.2510789],
      [-48.820055, -26.2510593],
      [-48.8201983, -26.2509017],
      [-48.8203162, -26.2507625]
    ],
    [
      [-48.8203162, -26.2507625],
      [-48.8204397, -26.2506083],
      [-48.8205047, -26.2505191],
      [-48.8205845, -26.2503918],
      [-48.8206899, -26.2501917]
    ],
    [
      [-48.852705, -26.2519869],
      [-48.8527296, -26.2519875]
    ],
    [
      [-48.8290973, -26.3759634],
      [-48.8289545, -26.3760711],
      [-48.8285324, -26.3764267],
      [-48.8281532, -26.3767526],
      [-48.8274298, -26.3773742]
    ],
    [
      [-48.8422361, -26.3245045],
      [-48.8422514, -26.3241954],
      [-48.8422568, -26.3240875]
    ],
    [
      [-48.8431803, -26.3430778],
      [-48.8431753, -26.3429906],
      [-48.8431657, -26.3429024],
      [-48.8431509, -26.3428157],
      [-48.8431314, -26.3427353],
      [-48.8431066, -26.3426517],
      [-48.8430697, -26.3425474],
      [-48.8430201, -26.3424412],
      [-48.8429632, -26.3423414],
      [-48.842873, -26.342219],
      [-48.8427673, -26.3420929]
    ],
    [
      [-48.8263729, -26.2708319],
      [-48.8265861, -26.2710177]
    ],
    [
      [-48.8433137, -26.2847354],
      [-48.843304, -26.2848902],
      [-48.8433411, -26.2849748]
    ],
    [
      [-48.8432317, -26.2852989],
      [-48.8432589, -26.2849562],
      [-48.8432765, -26.2848601],
      [-48.843288, -26.2847971],
      [-48.8433137, -26.2847354]
    ],
    [
      [-48.8428451, -26.2952296],
      [-48.8429679, -26.2950513],
      [-48.8429697, -26.2949963],
      [-48.8430451, -26.2926301],
      [-48.8430492, -26.2921255]
    ],
    [
      [-48.8286294, -26.3067808],
      [-48.8292566, -26.3062432]
    ],
    [
      [-48.8275916, -26.3085376],
      [-48.8275222, -26.3084692],
      [-48.8274689, -26.3084075],
      [-48.8274107, -26.3083295],
      [-48.8273167, -26.3081902]
    ],
    [
      [-48.826966, -26.3076704],
      [-48.8268996, -26.307572],
      [-48.8266902, -26.3072617]
    ],
    [
      [-48.8297614, -26.3102002],
      [-48.8296409, -26.3101084],
      [-48.8295176, -26.3100144]
    ],
    [
      [-48.8267557, -26.3212462],
      [-48.8267107, -26.3211902],
      [-48.8266532, -26.3211304],
      [-48.8265709, -26.3210543],
      [-48.826486, -26.3209901],
      [-48.8261836, -26.3207835],
      [-48.8260949, -26.320727],
      [-48.8259554, -26.3206498],
      [-48.8258861, -26.3206218],
      [-48.825806, -26.3206004]
    ],
    [
      [-48.825806, -26.3206004],
      [-48.8256334, -26.3205735],
      [-48.8254366, -26.3205614]
    ],
    [
      [-48.8178992, -26.236308],
      [-48.8177285, -26.2354851]
    ],
    [
      [-48.8181442, -26.2374234],
      [-48.8180581, -26.2370333],
      [-48.8180442, -26.2369704]
    ],
    [
      [-48.8181792, -26.2375803],
      [-48.8181442, -26.2374234]
    ],
    [
      [-48.8276299, -26.3118007],
      [-48.828457, -26.312455]
    ],
    [
      [-48.8539583, -26.2934416],
      [-48.8540353, -26.294325],
      [-48.8540439, -26.2944236]
    ],
    [
      [-48.8552673, -26.2986997],
      [-48.8550151, -26.298734],
      [-48.8548435, -26.2987574]
    ],
    [
      [-48.8535346, -26.2988776],
      [-48.8533395, -26.2988888],
      [-48.8532074, -26.2989161],
      [-48.8530867, -26.2989642]
    ],
    [
      [-48.8546547, -26.3083244],
      [-48.8545591, -26.3083915],
      [-48.8544671, -26.3084278],
      [-48.8543562, -26.3084456]
    ],
    [
      [-48.852825, -26.3056874],
      [-48.8531857, -26.3059982],
      [-48.8534429, -26.3062198],
      [-48.8535363, -26.3062857],
      [-48.8536347, -26.3063351],
      [-48.8537282, -26.3063743],
      [-48.8538174, -26.3064031],
      [-48.8543095, -26.3065267]
    ],
    [
      [-48.8627821, -26.3058721],
      [-48.8628008, -26.3059537],
      [-48.8628361, -26.3060687]
    ],
    [
      [-48.8629042, -26.3063902],
      [-48.8629165, -26.3065123],
      [-48.8629437, -26.3068341]
    ],
    [
      [-48.8628361, -26.3060687],
      [-48.8628713, -26.3062044],
      [-48.8628885, -26.3062875],
      [-48.8629042, -26.3063902]
    ],
    [
      [-48.8078093, -26.3250107],
      [-48.8079394, -26.3247519],
      [-48.8079625, -26.3247003],
      [-48.8079699, -26.3246458],
      [-48.8078632, -26.3240749],
      [-48.8077752, -26.3236057],
      [-48.807695, -26.3231375],
      [-48.8076204, -26.3226792]
    ],
    [
      [-48.8187287, -26.3338546],
      [-48.818675, -26.333866],
      [-48.8169631, -26.3342312]
    ],
    [
      [-48.8287045, -26.3172574],
      [-48.8286271, -26.3171459]
    ],
    [
      [-48.8327452, -26.3157466],
      [-48.8325901, -26.3157382],
      [-48.832487, -26.3157325]
    ],
    [
      [-48.8019535, -26.2243477],
      [-48.8020869, -26.2242454]
    ],
    [
      [-48.8014211, -26.2250798],
      [-48.8013493, -26.2249594],
      [-48.8013674, -26.2248403]
    ],
    [
      [-48.8177269, -26.2348746],
      [-48.8176055, -26.2348542]
    ],
    [
      [-48.8176767, -26.2344551],
      [-48.8178308, -26.2344969]
    ],
    [
      [-48.8922192, -26.2904295],
      [-48.892169, -26.2904192],
      [-48.8921478, -26.2903942],
      [-48.8921168, -26.2903588]
    ],
    [
      [-48.8871177, -26.2936146],
      [-48.8876501, -26.2932791],
      [-48.88776, -26.293207]
    ],
    [
      [-48.8844706, -26.2962025],
      [-48.8845377, -26.2962239]
    ],
    [
      [-48.8846143, -26.2964205],
      [-48.8844384, -26.2964989]
    ],
    [
      [-48.8849465, -26.2923072],
      [-48.8847914, -26.2932915],
      [-48.8843628, -26.2959279],
      [-48.8843684, -26.2959844],
      [-48.8843852, -26.2960343],
      [-48.8844106, -26.2960824],
      [-48.8844515, -26.2961293],
      [-48.8844706, -26.2962025],
      [-48.88448, -26.2962383],
      [-48.8844931, -26.2962888],
      [-48.8845852, -26.2963879],
      [-48.8846143, -26.2964205]
    ],
    [
      [-48.8500758, -26.2727324],
      [-48.8500355, -26.2727081],
      [-48.8499554, -26.2726689]
    ],
    [
      [-48.8500758, -26.2727324],
      [-48.85013, -26.2726823],
      [-48.8501274, -26.2726346]
    ],
    [
      [-48.8098836, -26.3221256],
      [-48.8142607, -26.3207831]
    ],
    [
      [-48.8089538, -26.3224714],
      [-48.8089776, -26.3225114],
      [-48.80901, -26.3225154],
      [-48.809032, -26.3225261],
      [-48.8090505, -26.322544],
      [-48.8090635, -26.3225797],
      [-48.80906, -26.3226278],
      [-48.809104, -26.3226476]
    ],
    [
      [-48.8090023, -26.3222101],
      [-48.8091186, -26.3221931]
    ],
    [
      [-48.8089727, -26.3210322],
      [-48.8090835, -26.321029]
    ],
    [
      [-48.8091098, -26.3183045],
      [-48.8092639, -26.318316]
    ],
    [
      [-48.8092621, -26.3163451],
      [-48.8094287, -26.3163521]
    ],
    [
      [-48.9235815, -26.2792588],
      [-48.9235112, -26.2791903],
      [-48.9235434, -26.2784965],
      [-48.9235313, -26.2784664],
      [-48.9235018, -26.2784412],
      [-48.9234616, -26.2784183],
      [-48.9234227, -26.2784015],
      [-48.923353, -26.2783822],
      [-48.9233561, -26.278293]
    ],
  ];

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
