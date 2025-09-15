import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:balanca/screens/scale_page.dart';

class DeviceListPage extends StatefulWidget {
  const DeviceListPage({super.key});

  @override
  State<DeviceListPage> createState() => _DeviceListPageState();
}

class _DeviceListPageState extends State<DeviceListPage> {
  final _adapter = FlutterBluetoothSerial.instance;
  bool _loadingBonded = false;
  bool _discovering = false;
  final Map<String, BluetoothDevice> _map = {};
  final Set<String> _bondedAddrs = {};
  StreamSubscription<BluetoothDiscoveryResult>? _discSub;

  @override
  void initState() {
    super.initState();
    _ensurePermissions().then((_) => _loadBonded());
  }

  Future<void> _ensurePermissions() async {
    final perms = <Permission>[
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ];
    await perms.request();
    final isEnabled = await _adapter.isEnabled ?? false;
    if (!isEnabled) await _adapter.requestEnable();
  }

  Future<void> _loadBonded() async {
    setState(() => _loadingBonded = true);
    try {
      final list = await _adapter.getBondedDevices();
      _bondedAddrs
        ..clear()
        ..addAll(list.map((e) => e.address));
      for (final d in list) {
        _map[d.address] = d;
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingBonded = false);
    }
  }

  void _toggleDiscovery() async {
    if (_discovering) {
      await _stopDiscovery();
      return;
    }
    setState(() => _discovering = true);
    _discSub = _adapter.startDiscovery().listen(
      (r) {
        final dev = r.device;
        if (dev.address.isNotEmpty) {
          _map[dev.address] = dev;
          if (mounted) setState(() {});
        }
      },
      onDone: () {
        _discovering = false;
        if (mounted) setState(() {});
      },
      onError: (_) {
        _discovering = false;
        if (mounted) setState(() {});
      },
    );
  }

  Future<void> _stopDiscovery() async {
    try {
      await _discSub?.cancel();
      _discSub = null;
      await _adapter.cancelDiscovery();
    } catch (_) {}
    if (mounted) setState(() => _discovering = false);
  }

  Future<void> _onTapDevice(BluetoothDevice d) async {
    if (_discovering) {
      await _stopDiscovery();
    }
    if (!_bondedAddrs.contains(d.address)) {
      final ok = await _adapter.bondDeviceAtAddress(d.address);
      if (ok != true) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Falha ao parear')));
        }
        return;
      }
      await _loadBonded();
    }
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ScalePage(macAddress: d.address)));
  }

  @override
  void dispose() {
    _discSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final devices =
        _map.values.toList()..sort((a, b) {
          final ab = _bondedAddrs.contains(a.address);
          final bb = _bondedAddrs.contains(b.address);
          if (ab != bb) return ab ? -1 : 1;
          final an = a.name ?? '';
          final bn = b.name ?? '';
          final c = an.compareTo(bn);
          return c != 0 ? c : a.address.compareTo(b.address);
        });
    return Scaffold(
      appBar: AppBar(
        title: const Text('Selecionar balança'),
        actions: [
          if (_loadingBonded)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Atualizar pareados',
            icon: const Icon(Icons.refresh),
            onPressed: _loadBonded,
          ),
          IconButton(
            tooltip: _discovering ? 'Parar busca' : 'Buscar dispositivos',
            icon: Icon(
              _discovering ? Icons.wifi_tethering_off : Icons.wifi_tethering,
            ),
            onPressed: _toggleDiscovery,
          ),
        ],
      ),
      body:
          devices.isEmpty
              ? const Center(
                child: Text(
                  'Nenhum dispositivo encontrado. Atualize pareados ou inicie a busca.',
                ),
              )
              : ListView.separated(
                itemBuilder: (_, i) {
                  final d = devices[i];
                  final bonded = _bondedAddrs.contains(d.address);
                  return ListTile(
                    leading: Icon(bonded ? Icons.link : Icons.link_outlined),
                    title: Text(
                      d.name?.isNotEmpty == true ? d.name! : 'Sem nome',
                    ),
                    subtitle: Text(d.address),
                    trailing:
                        bonded
                            ? const Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: Chip(label: Text('Pareado')),
                            )
                            : null,
                    onTap: () => _onTapDevice(d),
                  );
                },
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemCount: devices.length,
              ),
    );
  }
}
