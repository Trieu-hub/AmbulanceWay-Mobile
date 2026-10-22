import '../core/json_reader.dart';

enum UserRole { driver, patient }

/// Phiên đăng nhập lưu trên máy.
class AppSession {
  const AppSession({
    required this.role,
    required this.token,
    required this.loginName,
    required this.displayName,
    this.patientProfileId,
  });

  final UserRole role;
  final String token;

  /// Tên đăng nhập của tài xế hoặc số điện thoại của bệnh nhân.
  final String loginName;
  final String displayName;

  /// Chỉ có khi [role] là bệnh nhân.
  final int? patientProfileId;

  Map<String, dynamic> toJson() => {
        'role': role.name,
        'token': token,
        'loginName': loginName,
        'displayName': displayName,
        'patientProfileId': patientProfileId,
      };

  static AppSession? fromJson(Object? json) {
    final reader = JsonReader.tryFrom(json);
    if (reader == null) return null;
    final token = reader.stringOrNull('token');
    final roleName = reader.stringOrNull('role');
    if (token == null || roleName == null) return null;
    final role = UserRole.values.where((r) => r.name == roleName).firstOrNull;
    if (role == null) return null;
    return AppSession(
      role: role,
      token: token,
      loginName: reader.string('loginName'),
      displayName: reader.string('displayName'),
      patientProfileId: reader.intOrNull('patientProfileId'),
    );
  }
}
