# Chạy AmbulanceWay trên điện thoại Android thật và chụp ảnh cho báo cáo

Mô hình khi chạy thật: **laptop** chạy backend (ASP.NET + SQL Server), **điện thoại** cài app và kết nối tới laptop qua **cùng một mạng Wi-Fi**.

```
 Điện thoại (app)  ──Wi-Fi──>  Laptop: http://<IP laptop>:5199  (API + SignalR + web quản trị)
```

Nên chuẩn bị **2 điện thoại** (một đóng vai tài xế, một đóng vai người dân). Nếu chỉ có 1 điện thoại: điện thoại làm tài xế, còn vai người dân dùng trang web `/Patient/Sos` trên laptop (hoặc ngược lại).

---

## Bước 1. Bật backend trên laptop cho điện thoại truy cập được

1. Mở terminal ở thư mục gốc repo (`AmbulanceWay/`) và chạy bằng profile `lan` (nghe trên mọi địa chỉ mạng, không chỉ `localhost`):
   ```
   dotnet run --launch-profile lan
   ```
   Lần đầu Windows hỏi quyền tường lửa cho `dotnet`: tick **Private networks** rồi bấm **Allow access**.
   Nếu lỡ bấm Cancel, mở PowerShell **Run as Administrator** và chạy:
   ```
   netsh advfirewall firewall add rule name="AmbulanceWay 5199" dir=in action=allow protocol=TCP localport=5199
   ```
2. Tìm IP của laptop: ngay khi chạy xong, backend in sẵn dòng
   `Điện thoại (cùng Wi-Fi với máy này) nhập địa chỉ máy chủ trong app: http://192.168.1.10:5199`.
   Hoặc tự xem: chạy `ipconfig`, ở mục **Wireless LAN adapter Wi-Fi** lấy dòng **IPv4 Address**.
   Nếu backend in cảnh báo `Backend chỉ nhận kết nối từ chính máy này` nghĩa là đang chạy nhầm profile `http` (Visual Studio: chọn profile **lan** cạnh nút Run).
   **Không** nhập `localhost`, `127.0.0.1` hay `0.0.0.0` vào app trên điện thoại: `localhost` trên điện thoại là chính cái điện thoại, còn `0.0.0.0` chỉ là cách backend báo "nghe trên mọi mạng".
3. Kiểm tra từ **trình duyệt trên điện thoại** (đang bắt cùng Wi-Fi): mở `http://192.168.1.10:5199/api/mobile/ping`.
   Thấy `{"ok":true,"app":"AmbulanceWay",...}` là điện thoại đã nói chuyện được với laptop.
   Không vào được thì kiểm tra lại: cùng Wi-Fi chưa, tường lửa, và Wi-Fi công cộng/trường học thường chặn các máy nhìn thấy nhau (dùng **điểm phát Wi-Fi từ điện thoại** cho laptop bắt là chắc ăn nhất).
4. Tạo dữ liệu mẫu: trên laptop mở `http://localhost:5199`, đăng nhập `admin` / `123`, bấm **Tạo dữ liệu mẫu**.
   Có sẵn: tài xế `test_driver1` / `123`, `test_driver2` / `123`; bệnh nhân SĐT `0987654321`; tài khoản bệnh viện `bv_choray` / `123`, `bv_giadinh` / `123`.

## Bước 2. Cài app lên điện thoại

File cài đặt đã build sẵn:

| File | Dùng khi |
|---|---|
| `mobile/build/app/outputs/flutter-apk/app-release.apk` | **Nên dùng**: nhẹ, chạy mượt, dùng để demo và chụp ảnh |
| `mobile/build/app/outputs/flutter-apk/app-debug.apk` | Khi cần xem log lỗi lúc chạy |

Build lại khi có sửa code: trong thư mục `mobile/` chạy `flutter build apk --release`.

**Cách A: gửi file APK sang điện thoại (không cần cáp)**
1. Gửi `app-release.apk` qua Zalo (gửi cho "Cloud của tôi"), Google Drive hoặc cáp USB.
2. Trên điện thoại mở file. Android hỏi "Cho phép cài ứng dụng không rõ nguồn gốc" thì bật cho app đang mở file (Zalo, Files...).
3. Google Play Protect có thể cảnh báo vì app chưa lên cửa hàng: chọn **Vẫn cài đặt**.

**Cách B: cắm cáp USB và cài bằng Flutter**
1. Bật **Tùy chọn nhà phát triển**: Cài đặt → Thông tin điện thoại → chạm 7 lần vào **Số hiệu bản tạo** (Xiaomi: **Phiên bản MIUI/HyperOS**; Samsung: Thông tin phần mềm → **Số hiệu bản tạo**).
2. Trong Tùy chọn nhà phát triển, bật **Gỡ lỗi USB** (Xiaomi bật thêm **Cài đặt qua USB**).
3. Cắm cáp, trên điện thoại chọn **Cho phép gỡ lỗi USB**. Kiểm tra bằng `flutter devices`.
4. Trong `mobile/` chạy `flutter install --release` (hoặc `flutter run --release` để vừa cài vừa xem log).

## Bước 3. Trỏ app tới laptop và cấp quyền

1. Mở app → màn hình chào → biểu tượng **bánh răng** (Cài đặt máy chủ).
2. Nhập `http://192.168.1.10:5199` (IP ở Bước 1) → **Kiểm tra kết nối** → **Lưu**.
3. Cấp quyền khi app hỏi:
   - **Vị trí: "Khi dùng ứng dụng"**: bắt buộc để gửi SOS và để tài xế chia sẻ vị trí.
   - **Thông báo**: để nhận ca SOS mới / trạng thái ca khi app chạy nền.
4. Riêng điện thoại tài xế (để thử nhận ca khi tắt màn hình): Cài đặt → Ứng dụng → AmbulanceWay → **Pin: Không hạn chế**. Xiaomi/Oppo/Vivo hay tự tắt app chạy nền nếu không chỉnh mục này.

## Bước 4. Kịch bản demo đầy đủ (theo thứ tự này là chụp đủ ảnh cho báo cáo)

| # | Ai | Thao tác | Kết quả mong đợi |
|---|---|---|---|
| 1 | Tài xế | Đăng nhập `test_driver1` / `123` → **BẮT ĐẦU CA TRỰC** | Trạng thái Đang trực; thanh thông báo có dòng "AmbulanceWay: đang trực" |
| 2 | Người dân | **Chưa có hồ sơ? Đăng ký mới** (hoặc đăng nhập `0987654321`) → nhập OTP (bấm **Điền**) | Vào màn hình Cấp cứu khẩn cấp |
| 3 | Người dân | Chọn loại khẩn cấp, kiểm tra vị trí/địa chỉ (sai thì bấm **Chỉnh**) → **PHÁT TÍN HIỆU SOS** | Chuyển sang màn hình theo dõi, bước "Gửi SOS" |
| 4 | Tài xế | Hộp thoại **Ca cấp cứu mới** (đếm ngược 15 giây) → **NHẬN CA NGAY** | Bản đồ dẫn đường tới bệnh nhân, có hồ sơ y tế |
| 5 | Người dân | Theo dõi | Thấy tài xế, biển số, xe trên bản đồ, thời gian dự kiến |
| 6 | Tài xế | **Đã đón bệnh nhân** → chọn bệnh viện → **Đi tới** | Lộ trình chuyển sang bệnh viện |
| 7 | (Laptop) | Cổng bệnh viện `bv_choray` / `123` → **Tiếp nhận**, nhập phòng | Tài xế và người dân thấy tên bệnh viện + phòng |
| 8 | Tài xế | **Hoàn thành nhiệm vụ** → tab **Lịch sử** | Chuyến vừa chạy nằm trong lịch sử |
| 9 | Người dân | Chấm sao → **Gửi đánh giá** | Về màn hình chính |
| 10 | Người dân | Biểu tượng hồ sơ → **Sửa hồ sơ y tế** → thêm dị ứng thuốc → **Lưu** | Hồ sơ cập nhật; ca sau tài xế thấy thông tin mới |
| 11 | Người dân | Gửi SOS mới → khi tài xế đã nhận → **Hủy yêu cầu cấp cứu**, chọn lý do | Người dân về màn hình chính; tài xế nhận thông báo "Bệnh nhân đã hủy ca" kèm lý do |
| 12 | Tài xế | Tắt màn hình, người dân gửi SOS mới | Điện thoại tài xế rung + hiện thông báo "Ca cấp cứu mới" |

Không có GPS tốt trong phòng: ở tab **Tài khoản** của tài xế bật **Mô phỏng vị trí xe**, nhấn giữ trên bản đồ để đặt vị trí xe.

## Bước 5. Chụp ảnh màn hình

- **Trên điện thoại:** bấm đồng thời **Nguồn + Giảm âm lượng**. Ảnh nằm trong thư viện, mục *Screenshots*.
- **Qua cáp USB (ảnh nét, lưu thẳng vào laptop):** trong `mobile/` chạy
  ```
  flutter screenshot --out=anh_01_dang_nhap.png
  ```
  hoặc `adb exec-out screencap -p > anh_01.png` (adb nằm trong `%LOCALAPPDATA%\Android\Sdk\platform-tools`).

Mẹo cho ảnh báo cáo đẹp và đồng đều:
- Dùng chế độ sáng, cỡ chữ mặc định, pin và sóng đầy đủ (hoặc cắt bỏ thanh trạng thái).
- Đặt tên file theo số thứ tự chức năng (`01_dang_nhap_tai_xe.png`, ...) để chèn vào báo cáo không nhầm.
- Mỗi ảnh nên có dữ liệu "thật" (tên, địa chỉ có nghĩa), tránh "test", "abc".

### Danh sách ảnh nên chụp (khớp mục 2.2 của báo cáo)

| Ảnh | Màn hình | Thời điểm chụp |
|---|---|---|
| 01 | Màn hình chào (chọn vai trò) | Mở app lần đầu |
| 02 | Cài đặt máy chủ + Kiểm tra kết nối thành công | Bước 3 |
| 03 | Đăng ký hồ sơ y tế (form đã điền) | Kịch bản #2 |
| 04 | Nhập mã OTP | Kịch bản #2 |
| 05 | Màn hình Cấp cứu khẩn cấp (chọn loại, vị trí, nút SOS) | Kịch bản #3, trước khi bấm |
| 06 | Chọn vị trí trên bản đồ | Bấm **Chỉnh** ở ô vị trí |
| 07 | Đăng nhập tài xế | Kịch bản #1 |
| 08 | Tài xế đang trực, chờ ca | Kịch bản #1 |
| 09 | Hộp thoại Ca cấp cứu mới (đếm ngược) | Kịch bản #4 |
| 10 | Tài xế dẫn đường tới bệnh nhân + hồ sơ y tế | Kịch bản #4 |
| 11 | Người dân theo dõi xe đang tới (bản đồ + tài xế + ETA) | Kịch bản #5 |
| 12 | Tài xế chọn bệnh viện | Kịch bản #6 |
| 13 | Người dân thấy bệnh viện + phòng tiếp nhận | Kịch bản #7 |
| 14 | Đánh giá chuyến đi | Kịch bản #9 |
| 15 | Lịch sử chuyến của tài xế | Kịch bản #8 |
| 16 | Hồ sơ của tôi / Sửa hồ sơ y tế | Kịch bản #10 |
| 17 | Hộp thoại Hủy yêu cầu cấp cứu (chọn lý do) | Kịch bản #11 |
| 18 | Thông báo trên thanh thông báo khi tắt màn hình | Kịch bản #12 |
| 19–20 | (Web, chụp trên laptop) Bảng điều phối Admin, Cổng bệnh viện | Kịch bản #7 |

## Lỗi thường gặp

| Hiện tượng | Cách xử lý |
|---|---|
| Máy tính xin được OTP nhưng điện thoại báo lỗi có chữ `localhost` (hoặc `10.0.2.2`, `0.0.0.0`) | App trên điện thoại đang trỏ sai địa chỉ: `localhost` là chính điện thoại, `10.0.2.2` chỉ dùng cho máy ảo Android. Vào bánh răng → Cài đặt máy chủ, nhập `http://<IP laptop>:5199`. App tự cảnh báo màu vàng ở màn hình chào khi địa chỉ không dùng được trên thiết bị |
| App báo không kết nối được máy chủ | Mở `http://<IP>:5199/api/mobile/ping` trên trình duyệt điện thoại. Không được: sai IP, khác Wi-Fi, tường lửa, hoặc backend đang chạy profile `http` thay vì `lan` |
| IP laptop đổi sau khi khởi động lại Wi-Fi | Chạy lại `ipconfig`, sửa địa chỉ trong Cài đặt máy chủ của app |
| Tài xế không nhận được SOS | Tài xế phải **Bắt đầu ca trực** và có vị trí (GPS hoặc mô phỏng) trong bán kính 5 km quanh bệnh nhân. Không ai trong 5 km thì máy chủ gửi cho mọi tài xế đang trực |
| Không có thông báo khi tắt màn hình | Kiểm tra đã cấp quyền Thông báo, pin "Không hạn chế", và tài xế đang trực có GPS (dịch vụ nền chạy theo GPS) |
| Bản đồ trắng / không vẽ được đường | Điện thoại cần Internet để tải bản đồ OpenStreetMap và tìm đường OSRM. Không có thì app vẽ đường thẳng nét đứt |
| "Không thể cài đặt ứng dụng" | Gỡ bản AmbulanceWay cũ trước (khác chữ ký debug/release) rồi cài lại |
