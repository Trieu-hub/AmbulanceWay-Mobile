import 'dart:io';

/// iOS Simulator đặt sẵn biến môi trường này cho mọi app chạy trong nó.
bool isIosSimulator() => Platform.environment.containsKey('SIMULATOR_DEVICE_NAME');
