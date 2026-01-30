import 'package:flutter/material.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(const MeshApp());

class MeshApp extends StatelessWidget {
  const MeshApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const MeshScreen(),
    );
  }
}

class MeshScreen extends StatefulWidget {
  const MeshScreen({super.key});
  @override
  State<MeshScreen> createState() => _MeshScreenState();
}

class _MeshScreenState extends State<MeshScreen> {
  final String userName = "Node_${DateTime.now().millisecond}"; // 你的节点ID
  List<String> connectedDevices = []; // 已连接的邻居
  List<String> logs = []; // 日志显示

  @override
  void initState() {
    super.initState();
    requestPermissions(); // 启动即要权限
  }

  // 1. 自动请求权限（这是小白最容易闪退的地方）
  void requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
      Permission.nearbyWifiDevices,
    ].request();
    addLog("权限请求完成，准备启动组网...");
    startMesh();
  }

  // 2. 启动组网（同时广播和扫描）
  void startMesh() async {
    try {
      // 开启广告模式（让别人发现我）
      await Nearby().startAdvertising(
        userName, Strategy.P2P_CLUSTER,
        onConnectionInitiated: onInit,
        onConnectionResult: onResult,
        onDisconnected: onDisconnected,
      );
      // 开启扫描模式（发现别人）
      await Nearby().startDiscovery(
        userName, Strategy.P2P_CLUSTER,
        onEndpointFound: (id, name, serviceId) {
          addLog("发现邻居: $name，尝试握手...");
          Nearby().requestConnection(userName, id, onConnectionInitiated: onInit, onConnectionResult: onResult, onDisconnected: onDisconnected);
        },
        onEndpointLost: (id) => addLog("邻居离开: $id"),
      );
    } catch (e) { addLog("启动失败: $e"); }
  }

  // 3. 处理连接逻辑
  void onInit(String id, ConnectionInfo info) {
    Nearby().acceptConnection(id, onPayLoadReceived: (id, payload) {
      String msg = String.fromCharCodes(payload.bytes!);
      handleMessage(msg, id); // 处理收到的消息
    });
  }

  void onResult(String id, Status status) {
    if (status == Status.CONNECTED) {
      setState(() => connectedDevices.add(id));
      addLog("成功接入节点: $id");
    }
  }

  void onDisconnected(String id) {
    setState(() => connectedDevices.remove(id));
    addLog("节点断开: $id");
  }

  // 4. 【核心逻辑】多跳转发调度器
  void handleMessage(String rawData, String senderId) {
    // 假设数据格式为: 目标ID|原始发送者|内容
    List<String> parts = rawData.split('|');
    if (parts.length < 3) return;

    String targetId = parts[0];
    String originId = parts[1];
    String content = parts[2];

    if (targetId == userName) {
      addLog("收到私信 (来自 $originId): $content");
    } else {
      addLog("路由转发: 帮 $originId 传信给 $targetId");
      // 转发给除了来源以外的所有邻居
      for (var deviceId in connectedDevices) {
        if (deviceId != senderId) {
          Nearby().sendBytesPayload(deviceId, Uint8List.fromList(rawData.codeUnits));
        }
      }
    }
  }

  void addLog(String msg) {
    setState(() => logs.insert(0, "${DateTime.now().toString().substring(11, 19)}: $msg"));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Mesh节点: $userName")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text("当前在线邻居: ${connectedDevices.length} 个"),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: logs.length,
              itemBuilder: (c, i) => ListTile(title: Text(logs[i], style: const TextStyle(fontSize: 12))),
            ),
          ),
        ],
      ),
    );
  }
}
