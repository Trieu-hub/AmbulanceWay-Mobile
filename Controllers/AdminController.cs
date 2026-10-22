using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using BCrypt.Net;
using AmbulanceWay.Models;
using AmbulanceWay.Constants;
using AmbulanceWay.Data;

namespace AmbulanceWay.Controllers
{
    public class AdminController : Controller
    {
        private readonly AmbulanceWayDbContext _context;
        public AdminController(AmbulanceWayDbContext context)
        {
            _context = context;
        }

        // 1. Trang danh sách (Render khung HTML)
        public async Task<IActionResult> Index()
        {
            var role = HttpContext.Session.GetInt32(AppConstants.SessionRole);
            if (role != AppConstants.RoleValueAdmin) return RedirectToAction("Login", "Account"); // Role 1 có thể là hằng số

            // Thống kê sơ bộ cho Dashboard
            ViewBag.TotalCases = await _context.EmergencyCases.CountAsync();
            ViewBag.ActiveDrivers = await _context.Drivers.CountAsync(d => d.Status == AppConstants.StatusOnline);
            ViewBag.CompletedTrips = await _context.TripHistories.CountAsync(t => t.TripStatus == AppConstants.CaseStatusCompleted);
            
            // GIÁM SÁT: Hiển thị tất cả các ca đang hoạt động (Chưa hoàn thành và chưa hủy)
            ViewBag.RecentCases = await _context.EmergencyCases
                .Where(e => e.Status != AppConstants.CaseStatusCompleted 
                         && e.Status != AppConstants.CaseStatusCancelled)
                .OrderByDescending(e => e.CreatedAt)
                .ToListAsync();

            return View();
        }

        // 2. Mở trang Quản lý Tài xế (Dùng cho giao diện Ajax)
        public IActionResult UserManagement()
        {
            var role = HttpContext.Session.GetInt32(AppConstants.SessionRole); // Role 1 có thể là hằng số
            if (role != AppConstants.RoleValueAdmin) return RedirectToAction("Login", "Account");

            return View();
        }

        // Mở trang Bản đồ độc lập phục vụ đa màn hình
        public IActionResult Map()
        {
            var role = HttpContext.Session.GetInt32(AppConstants.SessionRole); // Role 1 có thể là hằng số
            if (role != AppConstants.RoleValueAdmin) return RedirectToAction("Login", "Account");

            return View();
        }

        // 3. API lấy danh sách User dạng JSON (Dành cho JavaScript vẽ bảng)
        [HttpGet]
public async Task<IActionResult> GetUsers()
{
    var users = await _context.Users
        .AsNoTracking()
        .OrderBy(u => u.Id)
        .Select(u => new { 
            id = u.Id,          
            username = u.Username, 
            role = u.Role, 
            status = u.Status, 
            createdAt = u.CreatedAt.ToString("dd/MM/yyyy") 
        })
        .ToListAsync();
    return Json(users);
}
        public class AddUserRequest
        {
            public string Username { get; set; } = null!;
            public string Password { get; set; } = null!;
            public string Role { get; set; } = "DRIVER";
            public string? DriverName { get; set; }
            public string? Phone { get; set; }
            public string? Vehicle { get; set; }
            public string? LicenseNo { get; set; }
            public string? Station { get; set; }
        }

        // 4. API Thêm User mới (Dùng cho Ajax)
        [HttpPost]
        [IgnoreAntiforgeryToken]
        public async Task<IActionResult> AddUser([FromBody] AddUserRequest req)
        {
            if (req == null || string.IsNullOrEmpty(req.Username) || string.IsNullOrEmpty(req.Password))
                return BadRequest(new { message = "Dữ liệu trống hoặc thiếu thông tin bắt buộc" });

            var exists = await _context.Users.AsNoTracking().AnyAsync(u => u.Username == req.Username.Trim());
            if (exists) return BadRequest(new { message = "Tên đăng nhập đã tồn tại!" });

            var strategy = _context.Database.CreateExecutionStrategy();
            return await strategy.ExecuteAsync<IActionResult>(async () =>
            {
                await using var transaction = await _context.Database.BeginTransactionAsync();
                try
                {
                    var user = new User
                    {
                        Username = req.Username.Trim(),
                        Password = BCrypt.Net.BCrypt.HashPassword(req.Password.Trim()), // Đã hash mật khẩu
                        Role = (req.Role == AppConstants.RoleDriver) ? AppConstants.RoleDriver : AppConstants.RoleAdmin,
                        Status = AppConstants.StatusActive
                    };
                    _context.Users.Add(user);
                    await _context.SaveChangesAsync();

                    if (user.Role == AppConstants.RoleDriver)
                    {
                        var driver = new Driver
                        {
                            UserId = user.Id,
                            DriverName = req.DriverName ?? user.Username,
                            Phone = req.Phone ?? "N/A",
                            Vehicle = req.Vehicle ?? "N/A",
                            LicenseNo = req.LicenseNo ?? "N/A",
                            Station = req.Station ?? "Bệnh viện Columbia Asia",
                            Status = AppConstants.StatusOnline
                        };
                        _context.Drivers.Add(driver);
                        await _context.SaveChangesAsync();
                    }
                    await transaction.CommitAsync();
                    return Ok(new { success = true });
                }
                catch (Exception ex)
                {
                    await transaction.RollbackAsync();
                    Console.WriteLine("Lỗi DB: " + ex.Message);
                    return BadRequest(new { message = ex.Message });
                }
            });
        }

        // 5. Load form chỉnh sửa (Trang Edit truyền thống)
        public async Task<IActionResult> Edit(int id)
        {
            var role = HttpContext.Session.GetInt32(AppConstants.SessionRole);
            if (role != AppConstants.RoleValueAdmin) return RedirectToAction("Login", "Account"); // Role 1 có thể là hằng số

            var user = await _context.Users.FindAsync(id);
            if (user == null) return NotFound();

            if (user.Role == AppConstants.RoleDriver)
            {
                var driver = await _context.Drivers.FirstOrDefaultAsync(d => d.UserId == user.Id);
                ViewBag.Driver = driver;
            }
            return View(user);
        }


        // 6. Xử lý cập nhật thông tin
        [HttpPost]
        public async Task<IActionResult> Update(User updatedUser, string? DriverName, string? Phone, string? Vehicle, string? LicenseNo, string? Station)
        {
            var role = HttpContext.Session.GetInt32(AppConstants.SessionRole);
            if (role != AppConstants.RoleValueAdmin) return RedirectToAction("Login", "Account");

            var user = await _context.Users.FindAsync(updatedUser.Id);
            if (user != null) // Nên hash mật khẩu nếu có cập nhật
            {
                user.Username = updatedUser.Username;
                if (!string.IsNullOrEmpty(updatedUser.Password))
                    user.Password = BCrypt.Net.BCrypt.HashPassword(updatedUser.Password); // Hash mật khẩu khi cập nhật
                user.Role = (updatedUser.Role == AppConstants.RoleDriver) ? AppConstants.RoleDriver : AppConstants.RoleAdmin;
                user.Status = updatedUser.Status;

                if (user.Role == AppConstants.RoleDriver)
                {
                    var driver = await _context.Drivers.FirstOrDefaultAsync(d => d.UserId == user.Id);
                    if (driver == null)
                    {
                        driver = new Driver
                        {
                            UserId = user.Id,
                            DriverName = DriverName ?? user.Username,
                            Phone = Phone ?? "N/A",
                            Vehicle = Vehicle ?? "N/A",
                            LicenseNo = LicenseNo ?? "N/A",
                            Station = Station ?? "Bệnh viện Columbia Asia", // Nên dùng hằng số hoặc lấy từ cấu hình
                            Status = AppConstants.StatusOnline
                        };
                        _context.Drivers.Add(driver);
                    }
                    else
                    {
                        driver.DriverName = DriverName ?? driver.DriverName;
                        driver.Phone = Phone ?? driver.Phone;
                        driver.Vehicle = Vehicle ?? driver.Vehicle;
                        driver.LicenseNo = LicenseNo ?? driver.LicenseNo;
                        driver.Station = Station ?? driver.Station; // TODO: Nên dùng hằng số hoặc lấy từ cấu hình
                    }
                }
                await _context.SaveChangesAsync();
            }
            return RedirectToAction("UserManagement");
        }

// 7. Xử lý Xóa User
        [HttpPost("/Admin/Delete/{id}")]
        public async Task<IActionResult> Delete(int id)
        {
            var role = HttpContext.Session.GetInt32(AppConstants.SessionRole); 
            if (role != AppConstants.RoleValueAdmin) return Forbid();

            var user = await _context.Users.FindAsync(id);
            if (user != null)
            {
                // Ngăn không cho tự xóa chính admin nếu cần
                if (user.Username.ToLower() == "admin") return BadRequest(new { message = "Không thể xóa Admin chính" });

                _context.Users.Remove(user);
                await _context.SaveChangesAsync();
                return Ok(new { success = true }); 
            }
            return NotFound();
        }

// 8. Trang quản lý Bệnh viện
        public IActionResult Hospitals()
        {
            var role = HttpContext.Session.GetInt32(AppConstants.SessionRole);
            if (role != AppConstants.RoleValueAdmin) return RedirectToAction("Login", "Account");

            return View();
        }

        // 9. Trang Lịch sử chuyến đi & Thống kê
        public IActionResult TripHistory()
        { // Role 1 có thể là hằng số
            var role = HttpContext.Session.GetInt32(AppConstants.SessionRole);
            if (role != AppConstants.RoleValueAdmin) return RedirectToAction("Login", "Account");

            return View();
        }

        // 10. API Seed dữ liệu mẫu để test nhanh các chức năng Admin
        [HttpPost]
        public async Task<IActionResult> SeedTestData() // Role 1 có thể là hằng số
        { // Role 1 có thể là hằng số
            var role = HttpContext.Session.GetInt32(AppConstants.SessionRole); 
            if (role != AppConstants.RoleValueAdmin) return Forbid();

            var strategy = _context.Database.CreateExecutionStrategy();
            return await strategy.ExecuteAsync<IActionResult>(async () =>
            {
                try
                {
                // 0. Thêm Patient Profile mẫu (Kiểm tra cả Tên và SĐT để tránh trùng)
                var testPatient = await _context.PatientProfiles.FirstOrDefaultAsync(p => p.FullName == "BN_TEST_01" || p.PhoneNumber == "0987654321");
                if (testPatient == null)
                {
                    testPatient = new PatientProfile
                    {
                        FullName = "BN_TEST_01",
                        PhoneNumber = "0987654321",
                        EmergencyContactName = "Người thân mẫu",
                        EmergencyContactPhone = "0901234567",
                        IsOtpVerified = true,
                        CreatedAt = DateTime.UtcNow,
                        BirthDate = new DateTime(1990, 1, 1),
                        Gender = "Nam",
                        PermanentAddress = "Địa chỉ mẫu, Quận 1"
                    };
                    _context.PatientProfiles.Add(testPatient);
                    await _context.SaveChangesAsync();
                }

                // 1. Thêm Bệnh viện mẫu (Tiền tố TEST_ để dễ quản lý)
                if (!await _context.Hospitals.AnyAsync(h => h.Name.StartsWith("TEST_")))
                {
                    _context.Hospitals.AddRange(new List<Hospital>
                    {
                        new Hospital { Name = "TEST_BV Gia Định", Lat = 10.801m, Lng = 106.691m, Address = "Bình Thạnh, HCM", TotalEmergencyBeds = 50, AvailableEmergencyBeds = 12, ReceptionStatus = "OPEN", IsActive = true, Type = "Public" },
                        new Hospital { Name = "TEST_BV Chợ Rẫy", Lat = 10.757m, Lng = 106.659m, Address = "Quận 5, HCM", TotalEmergencyBeds = 100, AvailableEmergencyBeds = 8, ReceptionStatus = "OPEN", IsActive = true, Type = "Public" }
                    });
                }

                // 2. Thêm Tài xế mẫu (Gồm User + Driver liên kết)
                if (!await _context.Users.AnyAsync(u => u.Username.StartsWith("test_driver")))
                {
                    for (int i = 1; i <= 2; i++)
                    {
                        var user = new User { Username = $"test_driver{i}", Password = BCrypt.Net.BCrypt.HashPassword("123"), Role = AppConstants.RoleDriver, Status = AppConstants.StatusActive, CreatedAt = DateTime.UtcNow }; // Đã hash mật khẩu, dùng hằng số
                        _context.Users.Add(user);
                        await _context.SaveChangesAsync(); // Lưu để lấy ID

                        _context.Drivers.Add(new Driver 
                        { 
                            UserId = user.Id, 
                            DriverName = $"Driver Test {i}", 
                            Vehicle = $"51A-TEST{i}", 
                            Phone = $"090000000{i}", 
                            LicenseNo = "TEST-LICENSE", 
                            Status = AppConstants.StatusOnline, 
                            Station = "TEST_BV Gia Định" 
                        });
                    }
                }

                // 3. Thêm Lịch sử chuyến đi mẫu (Để test trang TripHistory và Stats)
                if (!await _context.TripHistories.AnyAsync(t => t.DriverName.StartsWith("Driver Test")))
                {
                    _context.TripHistories.AddRange(new List<TripHistory>
                    {
                        new TripHistory { 
                            DriverName = "Driver Test 1", VehicleNo = "51A-TEST1", HospitalName = "TEST_BV Gia Định", 
                            PatientAddress = "123 Lê Lợi, Q1", PatientLat = 10.782m, PatientLng = 106.695m,
                            HospitalLat = 10.801m, HospitalLng = 106.691m,
                            DistanceKm = 4.5m, DurationMinutes = 12, 
                            TripStatus = "COMPLETED", CreatedAt = DateTime.UtcNow.AddHours(-1), 
                            CompletedAt = DateTime.UtcNow.AddMinutes(-50), OverallRating = 5, 
                            AttitudeRating = 5, TimeRating = 4 
                        },
                        new TripHistory { 
                            DriverName = "Driver Test 2", VehicleNo = "51A-TEST2", HospitalName = "TEST_BV Chợ Rẫy", 
                            PatientAddress = "456 Nguyễn Huệ, Q1", PatientLat = 10.774m, PatientLng = 106.704m,
                            HospitalLat = 10.757m, HospitalLng = 106.659m,
                            DistanceKm = 7.2m, DurationMinutes = 20, 
                            TripStatus = "COMPLETED", CreatedAt = DateTime.UtcNow.AddHours(-3), 
                            CompletedAt = DateTime.UtcNow.AddHours(-2.5), OverallRating = 4, 
                            AttitudeRating = 4, TimeRating = 5 
                        }
                    });
                }

                // 4. Thêm Ca cấp cứu đang OPEN (Để hiện trên dashboard điều phối)
                if (!await _context.EmergencyCases.AnyAsync(e => e.Description == "TEST_CASE_OPEN"))
                {
                    _context.EmergencyCases.Add(new EmergencyCase
                    {
                        EmergencyType = "Tai nạn giao thông",
                        Description = "TEST_CASE_OPEN",
                        PatientProfileId = testPatient.Id,
                        PatientLat = 10.776m,
                        PatientLng = 106.701m,
                        PatientAddress = "Phố đi bộ Nguyễn Huệ",
                        Status = AppConstants.HospitalReceptionOpen,
                        CreatedAt = DateTime.UtcNow
                    });
                }

                // 5. Thêm Đánh giá mẫu (Để test biểu đồ Rating)
                if (!await _context.PatientRatings.AnyAsync(r => r.Comment == "Dữ liệu test đánh giá"))
                {
                    var testCase = await _context.EmergencyCases.FirstOrDefaultAsync(e => e.Status == "COMPLETED" && e.Description == "Dữ liệu test hoàn thành");
                    if (testCase == null) // Nên dùng hằng số cho Status
                    { // Nên dùng hằng số cho Status
                        testCase = new EmergencyCase { 
                            Status = "COMPLETED", 
                            EmergencyType = "Khó thở", 
                            Description = "Dữ liệu test hoàn thành",
                            PatientProfileId = testPatient.Id, 
                            PatientAddress = "Địa chỉ mẫu",
                            PatientLat = 10.776m,
                            PatientLng = 106.701m,
                            CreatedAt = DateTime.UtcNow 
                        };
                        _context.EmergencyCases.Add(testCase);
                        await _context.SaveChangesAsync();
                    }

                    _context.PatientRatings.Add(new PatientRating
                    {
                        EmergencyCaseId = testCase.Id,
                        PatientProfileId = testPatient.Id,
                        OverallRating = 5,
                        ResponseTimeRating = 5,
                        DriverAttitudeRating = 5,
                        VehicleConditionRating = 4,
                        SituationHandlingRating = 5,
                        Comment = "Dữ liệu test đánh giá",
                        CreatedAt = DateTime.UtcNow
                    });
                }
                // 5. Tài khoản cổng bệnh viện cho 2 bệnh viện mẫu (mật khẩu 123)
                await _context.SaveChangesAsync(); // bệnh viện mới thêm ở bước 1 cần có Id
                var seedAccounts = new[]
                {
                    (Hospital: "TEST_BV Gia Định", Username: "bv_giadinh", FullName: "Khoa Cấp cứu BV Gia Định"),
                    (Hospital: "TEST_BV Chợ Rẫy", Username: "bv_choray", FullName: "Khoa Cấp cứu BV Chợ Rẫy")
                };
                foreach (var account in seedAccounts)
                {
                    var hospital = await _context.Hospitals.FirstOrDefaultAsync(h => h.Name == account.Hospital);
                    if (hospital == null || await _context.HospitalUsers.AnyAsync(u => u.Username == account.Username)) continue;
                    _context.HospitalUsers.Add(new HospitalUser
                    {
                        HospitalId = hospital.Id,
                        Username = account.Username,
                        Password = BCrypt.Net.BCrypt.HashPassword("123"),
                        FullName = account.FullName,
                        Status = AppConstants.StatusActive,
                        CreatedAt = DateTime.UtcNow
                    });
                }


                await _context.SaveChangesAsync();
                return Ok(new { message = "Đã tạo dữ liệu mẫu thành công (Hospitals, Drivers, Trips, tài khoản bệnh viện)!" });
            }
            catch (Exception ex)
            {
                var innerError = ex.InnerException != null ? ex.InnerException.Message : ex.Message;
                return BadRequest(new { message = "Lỗi khi tạo dữ liệu: " + innerError });
            }
            });
        }

        // 11. API Dọn dẹp toàn bộ dữ liệu test đã tạo
        [HttpPost]
        public async Task<IActionResult> ClearTestData()
        {
            var role = HttpContext.Session.GetInt32(AppConstants.SessionRole); 
            if (role != AppConstants.RoleValueAdmin) return Forbid();

            var strategy = _context.Database.CreateExecutionStrategy();
            return await strategy.ExecuteAsync<IActionResult>(async () =>
            {
                try
                {
                var testUsers = _context.Users.Where(u => u.Username.StartsWith("test_driver"));
                var testDrivers = _context.Drivers.Where(d => d.DriverName.StartsWith("Driver Test"));
                var testHospitals = _context.Hospitals.Where(h => h.Name.StartsWith("TEST_"));
                var testTrips = _context.TripHistories.Where(t => t.DriverName.StartsWith("Driver Test") || t.HospitalName.StartsWith("TEST_"));
                var testCases = _context.EmergencyCases.Where(e => e.Description == "TEST_CASE_OPEN" || e.EmergencyType == "Test");
                var testRatings = _context.PatientRatings.Where(r => r.Comment == "Dữ liệu test đánh giá");
                var testPatients = _context.PatientProfiles.Where(p => p.FullName == "BN_TEST_01");
                var testNotifs = _context.HospitalNotifications.Where(n => n.DriverName.StartsWith("Driver Test"));

                _context.HospitalNotifications.RemoveRange(testNotifs);
                _context.PatientRatings.RemoveRange(testRatings);
                _context.EmergencyCases.RemoveRange(testCases);
                _context.TripHistories.RemoveRange(testTrips);
                _context.Drivers.RemoveRange(testDrivers);
                _context.Users.RemoveRange(testUsers);
                _context.Hospitals.RemoveRange(testHospitals);
                _context.PatientProfiles.RemoveRange(testPatients);

                await _context.SaveChangesAsync();
                return Ok(new { message = "Đã dọn dẹp sạch sẽ toàn bộ dữ liệu mẫu!" });
            }
            catch (Exception ex)
            {
                return BadRequest(new { message = ex.Message });
            }
            });
        }

        public class HospitalAccountRequest
        {
            public int HospitalId { get; set; }
            public string Username { get; set; } = "";
            public string Password { get; set; } = "";
            public string? FullName { get; set; }
        }

        // 13. Danh sách tài khoản cổng bệnh viện của một bệnh viện
        [HttpGet]
        public async Task<IActionResult> HospitalAccounts(int hospitalId)
        {
            if (HttpContext.Session.GetInt32(AppConstants.SessionRole) != AppConstants.RoleValueAdmin)
                return StatusCode(StatusCodes.Status403Forbidden, new { message = "Chỉ quản trị viên được xem" });

            var accounts = await _context.HospitalUsers
                .AsNoTracking()
                .Where(u => u.HospitalId == hospitalId)
                .OrderBy(u => u.Id)
                .Select(u => new { id = u.Id, username = u.Username, fullName = u.FullName, status = u.Status })
                .ToListAsync();
            return Json(accounts);
        }

        // 14. Tạo tài khoản cổng bệnh viện, hoặc đặt lại mật khẩu nếu tài khoản đã thuộc bệnh viện này
        [HttpPost]
        public async Task<IActionResult> SaveHospitalAccount([FromBody] HospitalAccountRequest req)
        {
            if (HttpContext.Session.GetInt32(AppConstants.SessionRole) != AppConstants.RoleValueAdmin)
                return StatusCode(StatusCodes.Status403Forbidden, new { message = "Chỉ quản trị viên được tạo tài khoản" });

            var username = (req.Username ?? "").Trim();
            var password = (req.Password ?? "").Trim();
            if (username.Length < 3 || username.Length > 50 || username.Contains(' '))
                return BadRequest(new { message = "Tên đăng nhập 3-50 ký tự, không có khoảng trắng" });
            if (password.Length < 6)
                return BadRequest(new { message = "Mật khẩu tối thiểu 6 ký tự" });

            var hospital = await _context.Hospitals.FindAsync(req.HospitalId);
            if (hospital == null) return NotFound(new { message = "Không tìm thấy bệnh viện" });

            var existing = await _context.HospitalUsers.FirstOrDefaultAsync(u => u.Username == username);
            if (existing != null && existing.HospitalId != hospital.Id)
                return BadRequest(new { message = "Tên đăng nhập đã được dùng cho bệnh viện khác" });

            var fullName = string.IsNullOrWhiteSpace(req.FullName) ? $"Cấp cứu {hospital.Name}" : req.FullName.Trim();
            if (fullName.Length > 100) fullName = fullName.Substring(0, 100);

            var created = existing == null;
            if (created)
            {
                _context.HospitalUsers.Add(new HospitalUser
                {
                    HospitalId = hospital.Id,
                    Username = username,
                    Password = BCrypt.Net.BCrypt.HashPassword(password),
                    FullName = fullName,
                    Status = AppConstants.StatusActive,
                    CreatedAt = DateTime.UtcNow
                });
            }
            else
            {
                existing!.Password = BCrypt.Net.BCrypt.HashPassword(password);
                existing.FullName = fullName;
                existing.Status = AppConstants.StatusActive;
            }
            await _context.SaveChangesAsync();

            return Json(new { success = true, message = created ? "Đã tạo tài khoản bệnh viện" : "Đã đặt lại mật khẩu" });
        }

        // 12. API Xóa ca cấp cứu (Dùng cho nút dấu X để xóa thủ công)
        [HttpPost]
        [Route("Admin/DeleteEmergencyCase/{id}")]
        public async Task<IActionResult> DeleteEmergencyCase(int id)
        {
            var role = HttpContext.Session.GetInt32(AppConstants.SessionRole); 
            if (role != AppConstants.RoleValueAdmin) return Forbid();

            var ec = await _context.EmergencyCases.FindAsync(id);
            if (ec != null)
            {
                _context.EmergencyCases.Remove(ec);
                await _context.SaveChangesAsync();
                return Ok(new { success = true });
            }
            return NotFound();
        }
    }
}
