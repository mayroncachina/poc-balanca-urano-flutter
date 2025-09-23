import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

class ScalePage extends StatefulWidget {
  const ScalePage({super.key, required this.macAddress});
  final String macAddress;

  @override
  State<ScalePage> createState() => _ScalePageState();
}

class _ScalePageState extends State<ScalePage> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Ao retornar para esta página, limpar estado e tentar reconectar
    if (!_connecting && !_isConnected) {
      _pollTimer?.cancel();
      _pollTimer = null;
      _sub?.cancel();
      _sub = null;
      _connection = null;
      _connect();
    }
  }

  BluetoothConnection? _connection;
  StreamSubscription<Uint8List>? _sub;
  bool _connecting = false;
  bool _isConnected = false;
  String? _parsedWeight;
  String? _detectedProtocol;
  String _log = '';

  bool _showHexLog = false;
  bool _showLog = false;
  bool _weighing = false;
  Timer? _pollTimer;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // Solicita permissões antes de tentar conectar
    _ensurePermissions().then((granted) {
      _connect();
    });
  }

  Future<void> _ensurePermissions() async {
    final perms = <Permission>[
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ];
    await perms.request();
  }

  Future<void> _connect() async {
    if (_connecting || _isConnected) return;
    if (_connection != null) {
      await _disconnect();
    }
    setState(() {
      _connecting = true;
      _log = '';
      _isConnected = false;
      _parsedWeight = null;
    });
    try {
      final adapter = FlutterBluetoothSerial.instance;
      try {
        await adapter.cancelDiscovery();
      } catch (_) {}
      final isEnabled = await adapter.isEnabled ?? false;
      if (!isEnabled) await adapter.requestEnable();

      final address = widget.macAddress;
      _appendLog('Conectando a $address ...');
      await _ensureBondedOrPair(address);

      late BluetoothConnection conn;
      try {
        conn = await BluetoothConnection.toAddress(
          address,
        ).timeout(const Duration(seconds: 20));
      } on TimeoutException {
        _appendLog('Tempo esgotado ao conectar (timeout).');
        rethrow;
      }
      _connection = conn;
      _isConnected = true;
      _appendLog('Conectado.');
      _listen(conn);
    } catch (e) {
      _appendLog('Erro ao conectar: $e');
      _isConnected = false;
      await _disconnect();
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _ensureBondedOrPair(String address) async {
    try {
      final adapter = FlutterBluetoothSerial.instance;
      final bonded = await adapter.getBondedDevices();
      final isBonded = bonded.any((d) => d.address == address);
      if (isBonded) {
        _appendLog('Dispositivo já pareado.');
        return;
      }
      _appendLog('Dispositivo não pareado, iniciando pareamento...');
      final ok = await adapter.bondDeviceAtAddress(address);
      _appendLog(
        (ok ?? false)
            ? 'Pareamento concluído.'
            : 'Pareamento falhou ou cancelado.',
      );
    } catch (e) {
      _appendLog('Falha ao verificar/parear: $e');
    }
  }

  void _listen(BluetoothConnection conn) {
    _sub?.cancel();
    _sub = conn.input?.listen(
      (Uint8List data) {
        if (_showHexLog) {
          _appendLog('HEX ${_toHex(data)}');
        } else {
          final chunk = utf8.decode(data, allowMalformed: true);
          _appendLog(
            'TXT ${chunk.replaceAll('\n', '\\n').replaceAll('\r', '\\r')}',
          );
          // Usa função utilitária para extrair o peso, independente do formato
          final pesoExtraido = extractWeightFromString(chunk);
          _appendLog('Peso extraído: \'${pesoExtraido ?? '--'}\'');
          _parsedWeight = pesoExtraido ?? '--';
        }
        setState(() {});
      },
      onDone: () {
        _appendLog('Conexão encerrada pelo dispositivo.');
        _isConnected = false;
        setState(() {});
      },
      onError: (e) {
        _appendLog('Erro de leitura: $e');
        setState(() {});
      },
    );
  }

  Future<void> _sendEnq() async {
    await _sendEnqInternal(logSend: true);
  }

  Future<void> _sendEnqInternal({bool logSend = false}) async {
    final conn = _connection;
    if (conn == null) return;
    try {
      conn.output.add(Uint8List.fromList([0x05]));
      await conn.output.allSent;
      if (logSend) _appendLog('ENQ (0x05) enviado');
    } catch (e) {
      if (logSend) _appendLog('Falha ao enviar ENQ: $e');
    }
  }

  void _toggleWeighing() {
    if (!_isConnected) return;
    if (_weighing) {
      _stopWeighing();
    } else {
      _startWeighing();
    }
  }

  void _startWeighing() {
    _weighing = true;
    setState(() {});
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 300), (_) async {
      if (!_isConnected) return;
      if (_sending) return;
      _sending = true;
      try {
        await _sendEnqInternal(logSend: false);
      } finally {
        _sending = false;
      }
    });
  }

  void _stopWeighing() {
    _weighing = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    setState(() {});
  }

  String _toHex(Uint8List data) =>
      data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

  Future<void> _disconnect() async {
    _stopWeighing();
    await _sub?.cancel();
    _sub = null;
    if (_connection != null) {
      try {
        await _connection!.finish();
      } catch (_) {}
      _connection = null;
    }
    setState(() {
      _isConnected = false;
    });
  }

  void _appendLog(String msg) {
    _log = (_log + (msg.endsWith('\n') ? msg : '$msg\n'));
    setState(() {});
  }

  /// Extrai o valor do peso de uma string, suportando múltiplos formatos.
  String? extractWeightFromString(String input) {
    // 1. Formato Urano: "PESO: 0.5kg" ou "PESO: 193B * PESO: 0.5kgEP01"
    final urano = RegExp(
      r'PESO[^\d+\-]*([+\-]?\d+(?:[.,]\d+)?)\s*(kg|g)',
      caseSensitive: false,
    ).firstMatch(input);
    if (urano != null) {
      final valor = urano.group(1)!.replaceAll(',', '.');
      final unidade = urano.group(2)!.toLowerCase();
      return unidade == 'kg' ? '$valor kg' : '$valor g';
    }
    // 2. Qualquer número seguido de kg/g
    final fallback = RegExp(
      r'([+\-]?\d+(?:[.,]\d+)?)\s*(kg|g)',
      caseSensitive: false,
    ).firstMatch(input);
    if (fallback != null) {
      final valor = fallback.group(1)!.replaceAll(',', '.');
      final unidade = fallback.group(2)!.toLowerCase();
      return unidade == 'kg' ? '$valor kg' : '$valor g';
    }
    // 3. Apenas número (última linha, comum em balanças simples)
    final plain = RegExp(r'([+\-]?\d+(?:[.,]\d+)?)').firstMatch(input);
    if (plain != null) {
      final s = plain.group(1)!.replaceAll(',', '.');
      // Unidade padrão: kg
      return '$s g';
    }
    return null;
  }

  @override
  void dispose() {
    // Fechar imediatamente a conexão e cancelar assinatura na saída da tela
    _sub?.cancel();
    if (_connection != null) {
      try {
        _connection!.finish();
      } catch (_) {}
      _connection = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Balança Urano'),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear_all),
            onPressed: () => setState(() => _log = ''),
            tooltip: 'Limpar log',
          ),
          IconButton(
            icon: Icon(_showLog ? Icons.bug_report : Icons.bug_report_outlined),
            onPressed: () => setState(() => _showLog = !_showLog),
            tooltip: _showLog ? 'Esconder log' : 'Mostrar log',
          ),
          IconButton(
            icon: Icon(_showHexLog ? Icons.hexagon : Icons.hexagon_outlined),
            onPressed: () => setState(() => _showHexLog = !_showHexLog),
            tooltip: _showHexLog ? 'Mostrar texto' : 'Mostrar HEX',
          ),
          if (!_isConnected && !_connecting)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _connect,
              tooltip: 'Reconectar',
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _isConnected
                        ? 'Conectado'
                        : (_connecting ? 'Conectando...' : 'Desconectado'),
                    style: TextStyle(
                      color:
                          _isConnected
                              ? Colors.green
                              : (_connecting ? Colors.orange : Colors.red),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _isConnected ? _disconnect : _connect,
                  icon: Icon(_isConnected ? Icons.link_off : Icons.link),
                  label: Text(_isConnected ? 'Desconectar' : 'Conectar'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child:
                  _weighing
                      ? OutlinedButton.icon(
                        onPressed: _isConnected ? _toggleWeighing : null,
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: const Text('Parar pesagem'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(220, 48),
                        ),
                      )
                      : ElevatedButton.icon(
                        onPressed: _isConnected ? _toggleWeighing : null,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Iniciar pesagem'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(220, 48),
                        ),
                      ),
            ),
            if (_isConnected) ...[
              const SizedBox(height: 8),
              Center(
                child: ElevatedButton(
                  onPressed: _sendEnq,
                  child: const Text('Pegar o Peso'),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Peso',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _parsedWeight ?? '--',
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _detectedProtocol != null
                          ? 'Protocolo: $_detectedProtocol'
                          : 'Protocolo: --',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_showLog) ...[
              const SizedBox(height: 12),
              const Text('Log de dados'),
              const SizedBox(height: 6),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: SingleChildScrollView(
                    reverse: true,
                    child: Text(
                      _log,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
