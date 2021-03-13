import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'DirectionsProvider.dart';
import 'map.page.dart';

class MainMenu extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Buscar Rota"),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: RaisedButton(
              color: Colors.deepOrangeAccent,
              child: Text('Mapa de cicloviário de Joinville',
                  textAlign: TextAlign.center),
              onPressed: () {},
            ),
          ),
          const Divider(
            color: Colors.black,
            height: 20,
            thickness: 5,
            indent: 20,
            endIndent: 0,
          ),
          Expanded(
            child: RaisedButton(
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
          ),
        ],
      ),
    );
  }
}

