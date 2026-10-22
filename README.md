# AmbulanceWay

Hệ thống điều phối xe cấp cứu theo thời gian thực, gồm hai phần trong cùng một repo:

| Phần | Công nghệ | Dành cho | Thư mục |
|---|---|---|---|
| Backend + bản web | ASP.NET Core 8 MVC, EF Core (SQL Server LocalDB), SignalR | Quản trị viên, bệnh viện, tài xế và người dân | thư mục gốc |
| App di động | Flutter | Tài xế và bệnh nhân | [`mobile/`](mobile/README.md) |

App di động không có backend riêng: nó gọi REST API và SignalR của project ASP.NET.

## Phạm vi đồ án môn Lập trình trên thiết bị di động (ECMP177)

**Sản phẩm chính của đồ án là ứng dụng Flutter trong thư mục [`mobile/`](mobile/README.md).** Backend ASP.NET Core và các trang web quản trị đóng vai trò hỗ trợ (máy chủ cho app, trang điều phối và cổng bệnh viện).

| Phần | Nguồn gốc |
|---|---|
| App Flutter `mobile/` (toàn bộ) | Xây dựng mới cho môn học này |
| API riêng cho app: `Controllers/Mobile*.cs`, `MobileJwt.cs`, `JwtOrAdminSessionAttribute.cs`; đăng nhập OTP và token cho bệnh nhân (`PatientAuthController`); hủy SOS, sửa hồ sơ, giới hạn một ca/tài xế; CORS và cấu hình SignalR cho app (`Program.cs`) | Bổ sung cho môn học này |
| Backend ASP.NET Core gốc (mô hình dữ liệu, điều phối SOS, hub SignalR) và các trang web quản trị | **Kế thừa từ đồ án chuyên ngành (web) của một thành viên trong nhóm**, được sửa lỗi và làm lại giao diện trong quá trình làm đồ án này |

## Luồng nghiệp vụ

1. Bệnh nhân gửi tín hiệu SOS kèm vị trí.
2. Máy chủ báo cho các tài xế đang trực trong bán kính 5 km và cho quản trị viên.
3. Một tài xế nhận ca; bệnh nhân thấy xe đang tới và thời gian dự kiến.
4. Tài xế đón bệnh nhân, chọn bệnh viện, đưa tới nơi và đóng ca.
5. Bệnh nhân đánh giá chuyến đi; chuyến được ghi vào lịch sử.

## Chạy nhanh

Cần .NET 8 SDK, SQL Server LocalDB và (cho app) Flutter 3.47 trở lên.

```
dotnet run --launch-profile http
```

Mở `http://localhost:5199`, đăng nhập `admin` / `123`. Lần chạy đầu, database `AmbulanceSystem` được tạo tự động. Trên trang Admin, nút **Tạo dữ liệu mẫu** tạo sẵn tài xế `test_driver1` / `123`, bệnh nhân `0987654321` và hai bệnh viện.

Chạy app di động:

```
cd mobile
flutter pub get
flutter run -d chrome
```

Hướng dẫn chi tiết (điện thoại thật, kịch bản demo, kiểm thử) nằm trong [`mobile/README.md`](mobile/README.md).

## Các trang web

Tất cả đăng nhập từ `/Account/Login` (tab Quản trị / Tài xế / Bệnh viện / Người dân).

| Trang | Dành cho | Tài khoản thử (sau khi bấm **Tạo dữ liệu mẫu**) |
|---|---|---|
| `/Admin/Index` | Điều phối viên: hàng chờ SOS, bản đồ xe, bệnh viện, tài khoản, thống kê | `admin` / `123` |
| `/Home/Map` | Tài xế: bắt đầu ca trực, nhận ca, dẫn đường, chọn bệnh viện, lịch sử chuyến | `test_driver1` / `123` |
| `/HospitalPortal/Dashboard` | Bệnh viện: ca đang đến, tiếp nhận/từ chối, cập nhật số giường | `bv_choray` / `123`, `bv_giadinh` / `123` |
| `/Patient/Register` → `/Patient/Sos` | Người dân: đăng nhập bằng SĐT + OTP, gửi SOS, theo dõi xe, đánh giá | SĐT `0987654321` |

- Tài khoản cổng bệnh viện tạo ở Admin → **Bệnh viện** → nút **Tài khoản**.
- Máy không có GPS (máy tính để bàn): trên bản đồ tài xế bấm nút **Mô phỏng di chuyển**, xe sẽ tự chạy theo lộ trình; bấm lên bản đồ để đặt vị trí xe.
- Demo trọn luồng trên một máy: mở trang người dân và trang tài xế ở hai trình duyệt khác nhau (hoặc một cửa sổ ẩn danh) vì cùng trình duyệt dùng chung phiên đăng nhập.

## Cấu trúc thư mục gốc

```
Controllers/    Controller MVC và API. Các file Mobile*.cs là API riêng cho app (yêu cầu JWT)
Hubs/           AmbulanceHub (SignalR): vị trí xe, SOS, trạng thái ca
Models/         Entity và AmbulanceWayDbContext
Migrations/     Migration của EF Core
Views/          Giao diện Razor: Admin, Account (đăng nhập, bệnh nhân), Home (bản đồ tài xế)
wwwroot/        CSS, JS, ảnh, manifest và service worker của bản web
mobile/         App Flutter
```

## Xác thực

- **Bản web** dùng Session. Trang tài xế và trang SOS đổi phiên lấy JWT ngắn hạn (`GET /Home/DriverToken`, `GET /Patient/Token`) để gọi chung API với app.
- Phiên web của người dân chỉ mở sau khi xác thực OTP (`POST /Patient/OpenSession` kèm token từ `verify-otp`).
- **App di động** dùng JWT: tài xế lấy token ở `POST /api/auth/login`, bệnh nhân lấy token sau khi xác thực OTP ở `POST /api/patientauth/verify-otp`.

## Giới hạn hiện tại

- OTP chưa gửi SMS: máy chủ trả mã về cho client để thử nghiệm.
- Thông báo khi app chạy nền là thông báo cục bộ (dịch vụ nền khi tài xế đang trực), chưa có push qua FCM khi app bị tắt hẳn.
- Các API `/api/Sos` và hub SignalR chưa yêu cầu đăng nhập.
- Khóa JWT và mật khẩu `admin` mặc định trong mã nguồn chỉ dùng cho môi trường phát triển.
