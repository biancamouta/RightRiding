import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'menu.page.dart';


void main() {
  runApp(RightRidingApp());
}

class RightRidingApp extends StatelessWidget {  //stateless pode ser cacheavel pra sempre
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: MainMenu(),
        appBar: AppBar(
          title: Text("RightRiding"),
        ),
      ),
    );
  }
}
