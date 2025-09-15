import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:balanca/screens/device_list_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

// Observador de rotas para gerenciar eventos de navegação
final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Balança Urano',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const DeviceListPage(),
      navigatorObservers: [routeObserver],
      debugShowCheckedModeBanner: false,
    );
  }
}
