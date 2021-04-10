import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'DirectionsProvider.dart';
import 'map.page.dart';

class MainMenu extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    var height = MediaQuery.of(context).size.height;
    var width = MediaQuery.of(context).size.width;

    return Scaffold(
        body: Align(
      alignment: Alignment.topCenter,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.purple,
              Colors.pink[200],
            ],
          ),
        ),
        width: width * 1.0,
        child: Padding(
          padding: const EdgeInsets.only(top: 10.0, bottom: 10.0),
          child: Column(
            children: <Widget>[
              SizedBox(height: height * 0.25),
              Text(
                'RightRiding',
                textAlign: TextAlign.center,
                textScaleFactor: 4.5,
                style: GoogleFonts.charmonman(
                  color: Colors.white,
                  shadows: [
                    Shadow(
                      blurRadius: 10.0,
                      color: Colors.deepPurple,
                      offset: Offset(5.0, 5.0),
                    ),
                  ],
                ),
              ),
              SizedBox(height: height * 0.08),
              RaisedButton(
                color: Colors.purple[700],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30.0)),
                child:  Column(
                  children: [
                    SizedBox(height: 20),
                    Text(
                      'Consultar Rota',
                      textAlign: TextAlign.center,
                      textScaleFactor: 1.3,
                      style: GoogleFonts.montserrat(
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 20)
                  ],
                ),
                onPressed: () {
                  Navigator.push(
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
    ));
  }
}
