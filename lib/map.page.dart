import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'DirectionsProvider.dart';
import 'package:geocoding/geocoding.dart';

class MapPage extends StatefulWidget {
  @override
  _MapPageState createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  GoogleMapController mapController;
  CameraPosition _initialLocation =
      CameraPosition(target: LatLng(-26.2903102, -48.8623476), zoom: 13,);

  final startAddressController = TextEditingController();
  final destinationAddressController = TextEditingController();

  String _startAddress = '';
  String _destinationAddress = '';
  String _currentAddress = '';
  String _placeDistance;

  get locations => null;

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
              color: Colors.grey[400],
              width: 2,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(
              Radius.circular(10.0),
            ),
            borderSide: BorderSide(
              color: Colors.blue[300],
              width: 2,
            ),
          ),
          contentPadding: EdgeInsets.all(15),
          hintText: hint,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    var height = MediaQuery.of(context).size.height;
    var width = MediaQuery.of(context).size.width;
    var _placeDistance = 20;

    return Container(
      child: Scaffold(
        body: Stack(
          children: <Widget>[
            Consumer<DirectionProvider>(
              builder:
                  (BuildContext context, DirectionProvider api, Widget child) {
                return GoogleMap(
                  initialCameraPosition: _initialLocation,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  mapType: MapType.normal,
                  zoomGesturesEnabled: true,
                  zoomControlsEnabled: false,
                  markers: _createMarkers(),
                  polylines: api.currentRoute,
                  onMapCreated: (GoogleMapController controller) {
                    mapController = controller;
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
                            onPressed: (_startAddress != '' &&
                                _destinationAddress != '')
                                ? () async {

                              setState(() {
                                LatLng fromPoint = LatLng(-26.2873668,-48.8470739);
                                LatLng toPoint = LatLng(-26.2926669,-48.8476211);

                                var api =
                                Provider.of<DirectionProvider>(context, listen: false);
                                api.findDirections(_startAddress, _destinationAddress);

                                var left = min(fromPoint.latitude, toPoint.latitude);
                                var right = max(fromPoint.latitude, toPoint.latitude);
                                var top = max(fromPoint.longitude, toPoint.longitude);
                                var bottom = min(fromPoint.longitude, toPoint.longitude);

                                api.currentRoute.first.points.forEach((point) {
                                  left = min(left, point.latitude);
                                  right = max(right, point.latitude);
                                  top = max(top, point.longitude);
                                  bottom = min(bottom, point.longitude);
                                });

                                var bounds = LatLngBounds(
                                  southwest: LatLng(left, bottom),
                                  northeast: LatLng(right, top),
                                );

                                var cameraUpdate = CameraUpdate.newLatLngBounds(bounds, 50);
                                mapController.animateCamera(cameraUpdate);


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
          ],
        ),
      ),
    );
  }

  Set<Marker> _createMarkers() {
    var markers = Set<Marker>();

    markers.add(
      Marker(
          markerId: MarkerId("FromMarker"),
          position: LatLng(-26.2903102, -48.8623476)),
    );
    markers.add(
      Marker(
          markerId: MarkerId("ToMarker"),
          position: LatLng(-26.2903102, -48.8623476)),
    );
    return markers;
  }
}

