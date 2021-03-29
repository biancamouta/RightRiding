import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'menu.page.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  runApp(RightRidingApp());
}

class RightRidingApp extends StatelessWidget {
  //stateless pode ser cacheavel pra sempre
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: MainMenu(),
        appBar: AppBar(
          title: Text(
            "RR",
            textScaleFactor: 1.2,
            style: GoogleFonts.charmonman(
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: Colors.purple[800],
          toolbarHeight: 40,
          actions: <Widget>[
            Icon(Icons.directions_bike,color: Colors.white,)
          ],
        ),
      ),
    );
  }
}
