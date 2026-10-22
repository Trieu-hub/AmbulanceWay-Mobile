# AmbulanceWay Mobile

Ứng dụng di động (Flutter) của hệ thống điều phối xe cấp cứu AmbulanceWay, dành cho hai vai trò:

- **Bệnh nhân / người nhà:** đăng ký và sửa hồ sơ y tế, đăng nhập bằng số điện thoại + OTP, gửi tín hiệu SOS kèm vị trí, theo dõi xe cấp cứu trên bản đồ theo thời gian thực, hủy yêu cầu khi xe chưa đón, đánh giá sau chuyến, nhận thông báo trạng thái ca khi app chạy nền.
- **Tài xế xe cấp cứu:** đăng ký / đăng nhập, vào và kết thúc ca trực, nhận SOS realtime (kể cả khi tắt màn hình: thông báo + rung), dẫn đường tới bệnh nhân, chọn bệnh viện, hoàn thành ca, xem lịch sử chuyến.

Hướng dẫn cài lên **điện thoại Android thật**, kịch bản demo và danh sách ảnh cần chụp cho báo cáo: [HUONG_DAN_DIEN_THOAI.md](HUONG_DAN_DIEN_THOAI.md).

Quản trị viên và cổng bệnh viện vẫn dùng bản web. App **không có backend riêng**: nó gọi REST API và SignalR của project ASP.NET Core ở thư mục gốc của repo.

## Chạy thử

Cần Flutter 3.47 trở lên và .NET 8.

**1. Bật backend** (ở thư mục gốc repo):

```
dotnet run --launch-profile http
```

Backend chạy ở `http://localhost:5199`. Để có dữ liệu mẫu, đăng nhập bản web bằng `admin` / `123` rồi bấm nút **Tạo dữ liệu mẫu** (biểu tượng cơ sở dữ liệu màu xanh) trên trang Admin. Nút này tạo tài xế `test_driver1` và `test_driver2` (mật khẩu `123`), hai bệnh viện và hồ sơ bệnh nhân có số điện thoại `0987654321`.

**2. Chạy app** (ở thư mục `mobile/`):

```
flutter pub get
flutter run -d chrome
```

Trên trình duyệt, hãy cho phép quyền vị trí khi được hỏi.

### Chạy trên điện thoại hoặc máy ảo

| Thiết bị | Cách bật backend | Địa chỉ máy chủ nhập trong app |
|---|---|---|
| Chrome / Windows trên cùng máy | `dotnet run --launch-profile http` | `http://localhost:5199` (mặc định) |
| Máy ảo Android | `dotnet run --launch-profile http` | `http://10.0.2.2:5199` (mặc định trên Android) |
| Điện thoại thật cùng Wi-Fi | `dotnet run --launch-profile lan` | `http://<IP máy tính>:5199` |

Đổi địa chỉ máy chủ bằng biểu tượng bánh răng ở màn hình chào; nút **Kiểm tra kết nối** cho biết địa chỉ có đúng không. Cũng có thể đặt sẵn lúc chạy:

```
flutter run --dart-define=API_BASE_URL=http://192.168.1.10:5199
```

Profile `lan` cho backend nghe trên mọi địa chỉ mạng, nên mọi máy trong cùng Wi-Fi đều truy cập được (kể cả tài khoản `admin` / `123`). Chỉ dùng trong mạng tin cậy, và Windows có thể hỏi quyền tường lửa ở lần chạy đầu.

Build Android lần đầu cần chấp nhận giấy phép của Android SDK: chạy `flutter doctor --android-licenses`.

Bản Windows desktop (`flutter run -d windows`) cần bật **Developer Mode** của Windows vì app có dùng plugin.

## Kịch bản demo

Mở hai cửa sổ app: một cho bệnh nhân, một cho tài xế. Trên trình duyệt, hai cửa sổ phải ở hai nguồn khác nhau (ví dụ một cửa sổ thường và một cửa sổ ẩn danh) để không dùng chung phiên đăng nhập.

1. **Tài xế:** đăng nhập `test_driver1` / `123` → **Bắt đầu ca trực**.
2. **Bệnh nhân:** đăng ký hồ sơ mới (hoặc đăng nhập `0987654321`) → nhập mã OTP → chọn loại khẩn cấp → **Phát tín hiệu SOS**.
3. **Tài xế:** hộp thoại "Ca cấp cứu mới" hiện trong 15 giây → **Nhận ca ngay**. Hết giờ thì ca vẫn nằm trong **Ca đang chờ**.
4. **Bệnh nhân:** thấy tên tài xế, biển số, vị trí xe và thời gian dự kiến.
5. **Tài xế:** **Đã đón bệnh nhân** → chọn bệnh viện (**Đi tới**) → **Hoàn thành nhiệm vụ**.
6. **Bệnh nhân:** chấm sao và gửi đánh giá. Tài xế xem lại chuyến ở tab **Lịch sử**.
7. **Bệnh nhân:** gửi SOS khác, khi tài xế đã nhận thì bấm **Hủy yêu cầu cấp cứu** và chọn lý do; tài xế nhận thông báo hủy và nhiệm vụ được gỡ.

**Mô phỏng xe di chuyển khi không có GPS** (máy tính, máy ảo): vào tab **Tài khoản** của tài xế, bật **Mô phỏng vị trí xe**, rồi nhấn giữ trên bản đồ để đặt vị trí xe. Vị trí này được gửi lên máy chủ như GPS thật nên màn hình bệnh nhân cũng thấy xe di chuyển.

## Cấu trúc mã nguồn

```
lib/
  main.dart, app.dart      Khởi động, giao diện chung, chọn màn hình theo phiên đăng nhập
  core/                    Cấu hình, gọi REST (ApiClient), đọc JSON, tính khoảng cách
  models/                  Dữ liệu: phiên đăng nhập, tài xế, bệnh nhân, bệnh viện, lộ trình
  services/                Từng nhóm API, SignalR (HubClient), GPS, tìm đường, tra địa chỉ
  state/                   Nghiệp vụ: AppState, DriverController, PatientController
  screens/                 Màn hình chào, cài đặt máy chủ, driver/, patient/
  widgets/                 Bản đồ và các thành phần dùng chung
test/                      Kiểm thử đơn vị, widget và đầu-cuối
```

Toàn bộ nghiệp vụ nằm trong `state/`; các màn hình chỉ hiển thị và gọi hàm của controller. Quản lý trạng thái bằng `provider`.

## Backend mà app sử dụng

| Việc | API |
|---|---|
| Đăng nhập tài xế | `POST /api/auth/login` |
| Đăng ký tài xế | `POST /Account/RegisterDriver` |
| Đăng ký / đăng nhập bệnh nhân | `POST /api/patientauth/register`, `/login`, `/verify-otp` |
| Ca trực | `POST /api/duty/start`, `/end`, `GET /api/duty/current` |
| Gửi SOS, nhận ca, cập nhật trạng thái | `POST /api/Sos`, `POST /api/Sos/{id}/accept`, `PUT /api/Sos/{id}/status` |
| Danh sách bệnh viện | `GET /api/Hospitals` |
| Riêng cho app tài xế | `/api/mobile/driver/*` (hồ sơ, ca đang chờ, ca đang làm, bệnh viện đích, lịch sử) |
| Riêng cho app bệnh nhân | `/api/mobile/patient/*` (xem/sửa hồ sơ, trạng thái ca, hủy ca, đánh giá) |
| Kiểm tra kết nối | `GET /api/mobile/ping` |
| Realtime | SignalR hub `/ambulanceHub` (thêm sự kiện `CaseCancelled` khi bệnh nhân hủy ca) |

Các API `/api/mobile/*` yêu cầu JWT và nằm trong `Controllers/Mobile*.cs`.

Dịch vụ ngoài: ô bản đồ OpenStreetMap, tìm đường OSRM (`router.project-osrm.org`) và tra địa chỉ Nominatim. Mất kết nối tới OSRM thì app vẽ đường thẳng nét đứt và ước lượng khoảng cách.

## Kiểm thử

```
flutter analyze
flutter test
```

`flutter test` chạy kiểm thử đơn vị và widget với backend và SignalR giả, không cần mạng.

Kiểm thử đầu-cuối với backend thật (đi hết luồng SOS → nhận ca → đón → chọn viện → hoàn thành → đánh giá, rồi sửa hồ sơ và hủy một SOS thứ hai, qua REST và SignalR):

```
flutter test test/live --dart-define=API_BASE=http://localhost:5199
```

Bài này tạo dữ liệu thật (một tài xế, một bệnh nhân, một bệnh viện, một ca), nên chỉ chạy với cơ sở dữ liệu thử nghiệm.

## Giới hạn hiện tại

- **OTP chưa gửi SMS.** Backend trả mã về cho app và app hiển thị mã đó, nên ai biết số điện thoại cũng đăng nhập được hồ sơ tương ứng. Cần nối nhà cung cấp SMS trước khi dùng thật.
- **Thông báo khi chạy nền là thông báo cục bộ, chưa phải push qua máy chủ (FCM).** Tài xế đang trực có GPS thì app chạy dịch vụ nền (thông báo thường trực "đang trực") nên vẫn giữ kết nối và hiện thông báo + rung khi có SOS mới. Nhưng nếu người dùng vuốt tắt hẳn app, hoặc máy tiết kiệm pin dừng app, thì không còn nhận được gì cho tới khi mở lại. Bệnh nhân nhận thông báo trạng thái khi app đang chạy nền.
- **Backend chạy HTTP.** Bản Android và iOS đang cho phép kết nối không mã hóa để thử trong mạng nội bộ (`usesCleartextTraffic`, `NSAllowsArbitraryLoads`); bỏ hai thiết lập này khi triển khai qua HTTPS.
- **Token lưu bằng `shared_preferences`**, chưa dùng kho lưu bảo mật của hệ điều hành.
- **Chỉ hủy SOS được trước khi xe đón bệnh nhân.** Sau khi đã đón thì phải liên hệ tài xế hoặc gọi 115.
- **Không đổi được số điện thoại** trong hồ sơ, vì số điện thoại là định danh đăng nhập bằng OTP.
