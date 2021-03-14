import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'DirectionsProvider.dart';
import 'map.page.dart';

class MainMenu extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    var height = MediaQuery
        .of(context)
        .size
        .height;
    var width = MediaQuery
        .of(context)
        .size
        .width;

    return Scaffold(
      body: Align(
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
                children: <Widget>[
                  SizedBox(height: 10),
                  RaisedButton(
                    color: Colors.deepOrangeAccent,
                    child: Text('Mapa de cicloviário de Joinville',
                        textAlign: TextAlign.center),
                    onPressed: () {},
                  ),
                  SizedBox(height: 10),
                  RaisedButton(
                    color: Colors.amberAccent,
                    child: Text('Consultar Rota', textAlign: TextAlign.center),
                    onPressed: () {
                      final Future<Route> future = Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) {
                            return ChangeNotifierProvider(
                              create: (_) => DirectionProvider(),
                              child: MaterialApp(
                                home: MapPage(),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
