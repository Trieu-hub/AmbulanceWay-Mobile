import '../core/api_client.dart';
import '../core/json_reader.dart';
import '../models/patient_models.dart';
import '../models/session.dart';

/// Đăng nhập / đăng ký cho cả tài xế và bệnh nhân.
class AuthService {
  AuthService(this._api);

  final ApiClient _api;

  /// POST /api/auth/login - chỉ nhận tài khoản có vai trò DRIVER.
  Future<AppSession> loginDriver(String username, String password) async {
    final data = JsonReader.tryFrom(await _api.post('/api/auth/login', body: {
      'Username': username.trim(),
      'Password': password,
    }));

    final token = data?.stringOrNull('token');
    if (token == null) {
      throw ApiException('Máy chủ không trả về token đăng nhập.');
    }

    final user = data?.object('user');
    if (user?.string('role') != 'DRIVER') {
      throw ApiException(
          'Tài khoản này không phải tài xế. Quản trị viên và bệnh viện vui lòng dùng bản web.');
    }

    final name = user?.string('username', username.trim()) ?? username.trim();
    return AppSession(
      role: UserRole.driver,
      token: token,
      loginName: name,
      displayName: name,
    );
  }

  /// POST /Account/RegisterDriver - dùng lại action đăng ký tài xế của bản web (gửi dạng form).
  Future<String> registerDriver({
    required String username,
    required String password,
    required String fullName,
    required String vehicleNo,
    required String licenseNo,
  }) async {
    final data = JsonReader.tryFrom(await _api.postForm('/Account/RegisterDriver', {
      'Username': username.trim(),
      'Password': password,
      'FullName': fullName.trim(),
      'VehicleNo': vehicleNo.trim(),
      'LicenseNo': licenseNo.trim(),
    }));

    if (data == null || !data.boolean('success')) {
      throw ApiException(data?.stringOrNull('message') ?? 'Đăng ký không thành công.');
    }
    return data.string('message', 'Đăng ký thành công!');
  }

  /// POST /api/patientauth/register - tạo/cập nhật hồ sơ và xin mã OTP.
  Future<OtpTicket> registerPatient(PatientRegistration form) async {
    final data = JsonReader.tryFrom(
        await _api.post('/api/patientauth/register', body: form.toJson()));
    return _ticket(form.phoneNumber, data);
  }

  /// POST /api/patientauth/login - bệnh nhân đã có hồ sơ xin mã OTP để đăng nhập lại.
  Future<OtpTicket> requestPatientOtp(String phoneNumber) async {
    final phone = phoneNumber.trim();
    final data = JsonReader.tryFrom(
        await _api.post('/api/patientauth/login', body: {'PhoneNumber': phone}));
    return _ticket(phone, data);
  }

  OtpTicket _ticket(String phone, JsonReader? data) => OtpTicket(
        phoneNumber: phone,
        devOtp: data?.stringOrNull('otp'),
        expiresInSeconds: data?.integer('expiresInSeconds', 300) ?? 300,
      );

  /// POST /api/patientauth/verify-otp - đúng mã thì nhận token + mã hồ sơ.
  Future<AppSession> verifyPatientOtp(String phoneNumber, String otpCode) async {
    final phone = phoneNumber.trim();
    final data = JsonReader.tryFrom(await _api.post('/api/patientauth/verify-otp', body: {
      'PhoneNumber': phone,
      'OtpCode': otpCode.trim(),
    }));

    final token = data?.stringOrNull('token');
    final profileId = data?.intOrNull('profileId');
    if (token == null || profileId == null) {
      throw ApiException(
          'Máy chủ chưa hỗ trợ đăng nhập bệnh nhân cho app. Hãy cập nhật backend mới nhất.');
    }

    return AppSession(
      role: UserRole.patient,
      token: token,
      loginName: phone,
      displayName: data?.string('fullName', phone) ?? phone,
      patientProfileId: profileId,
    );
  }
}
