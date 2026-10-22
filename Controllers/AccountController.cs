using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Http;
using Microsoft.EntityFrameworkCore;
using AmbulanceWay.Data;
using AmbulanceWay.Constants;
using BCrypt.Net;
using AmbulanceWay.Models;
using System.Globalization;

namespace AmbulanceWay.Controllers
{
    public class AccountController : Controller
    {
        private readonly AmbulanceWayDbContext _context;

        // internal: MobileDriverController dùng lại bảng tọa độ trạm này
        internal static readonly Dictionary<string, (double lat, double lng)> StationCoords = new(StringComparer.OrdinalIgnoreCase)
        {
            ["Bệnh viện Columbia Asia"] = (10.80165, 106.69796),
            ["Trạm Bình Thạnh"] = (10.8020, 106.7150),
            ["Trạm Quận 1"] = (10.7758, 106.7009),
            ["Trạm Thủ Đức"] = (10.8500, 106.7700),
            ["Trạm Gò Vấp"] = (10.8300, 106.6900),
        };

        public AccountController(AmbulanceWayDbContext context)
        {
            _context = context;
        }

        [HttpGet]
        public IActionResult Login()
        {
            if (HttpContext.Session.GetString(AppConstants.SessionUsername) != null)
            {
                var role = HttpContext.Session.GetInt32(AppConstants.SessionRole);
                if (role == AppConstants.RoleValueAdmin) 
                    return RedirectToAction("Index", "Admin");
                if (role == AppConstants.RoleValueHospital) 
                    return RedirectToAction("Dashboard", "HospitalPortalMvc");
                if (role == AppConstants.RoleValuePatient) 
                    return RedirectToAction("Sos", "Patient");
                
                // Mặc định cho tài xế
                return RedirectToAction("Map", "Home"); 
            }
            return View();
        }

        [HttpPost]
        public async Task<IActionResult> RegisterDriver(DriverRegistrationModel model)
        {
            if (model == null || string.IsNullOrWhiteSpace(model.Username) || string.IsNullOrWhiteSpace(model.Password))
                return Json(new { success = false, message = "Vui lòng nhập đầy đủ Tên và Mật khẩu" });

            var exists = await _context.Users.AsNoTracking().AnyAsync(u => u.Username == model.Username.Trim());
            if (exists) return Json(new { success = false, message = "Tên đăng nhập này đã được sử dụng" });

            var strategy = _context.Database.CreateExecutionStrategy();
            return await strategy.ExecuteAsync<IActionResult>(async () =>
            {
                await using var transaction = await _context.Database.BeginTransactionAsync();
                try
                {
                    var user = new User
                    {
                        Username = model.Username.Trim(),
                        Password = BCrypt.Net.BCrypt.HashPassword(model.Password.Trim()),
                        CreatedAt = DateTime.UtcNow,
                        Role = AppConstants.RoleDriver,
                        Status = AppConstants.StatusActive
                    };
                    _context.Users.Add(user);
                    await _context.SaveChangesAsync();

                    var driver = new Driver
                    {
                        UserId = user.Id,
                        DriverName = model.FullName ?? model.Username,
                        Phone = "000",
                        Vehicle = model.VehicleNo ?? "Chưa cập nhật",
                        LicenseNo = model.LicenseNo ?? "N/A",
                        Station = "Bệnh viện Columbia Asia",
                        Status = AppConstants.StatusOnline
                    };
                    _context.Drivers.Add(driver);
                    await _context.SaveChangesAsync();

                    await transaction.CommitAsync();
                    return Json(new { success = true, message = "Đăng ký thành công! Bạn có thể đăng nhập ngay." });
                }
                catch (Exception ex)
                {
                    await transaction.RollbackAsync();
                    var innerExceptionMessage = ex.InnerException != null ? ex.InnerException.Message : ex.Message;
                    Console.WriteLine($"Error during driver registration: {innerExceptionMessage}");
                    return Json(new { success = false, message = "Lỗi DB: " + innerExceptionMessage });
                }
            });
        }

        public class DriverRegistrationModel
        {
            public string Username { get; set; } = null!;
            public string Password { get; set; } = null!;
            public string? FullName { get; set; }
            public string? VehicleNo { get; set; }
            public string? LicenseNo { get; set; }
        }

        // Trang OTP riêng đã gộp vào /Patient/Register (nhập OTP ngay trên trang đăng nhập bệnh nhân)
        [HttpGet]
        public IActionResult VerifyOtp() => RedirectToAction("Register", "Patient");

        [HttpPost]
        public async Task<IActionResult> Login(string username, string password)
        {
            try
            {
                string cleanUsername = (username ?? "").Trim();
                string cleanPassword = (password ?? "").Trim();

                if (string.IsNullOrEmpty(cleanUsername) || string.IsNullOrEmpty(cleanPassword))
                    return Json(new { success = false, message = "Vui lòng nhập đầy đủ thông tin!" });

                // Tìm user không phân biệt hoa thường (để gõ Admin hay admin đều được)
                var user = await _context.Users.AsNoTracking()
                    .FirstOrDefaultAsync(u => u.Username.ToLower() == cleanUsername.ToLower());

                if (user == null)
                    return Json(new { success = false, message = "Sai tài khoản hoặc mật khẩu!" });

                // Xác thực mật khẩu
                bool isPasswordValid = false;
                try
                {
                    isPasswordValid = BCrypt.Net.BCrypt.Verify(cleanPassword, user.Password);
                }
                catch
                {
                    // Nếu mật khẩu trong DB chưa được hash (ví dụ nhập tay "123"), so sánh trực tiếp
                    isPasswordValid = (user.Password == cleanPassword);
                }

                if (!isPasswordValid)
                    return Json(new { success = false, message = "Sai tài khoản hoặc mật khẩu!" });

                if (user.Status != AppConstants.StatusActive)
                    return Json(new { success = false, message = "Tài khoản đang bị khóa!" });

                if (user.Role == AppConstants.RoleAdmin)
                {
                    SetAdminSession(user.Username ?? cleanUsername, user.Username ?? cleanUsername);
                    return Json(new { success = true, redirectUrl = "/Admin/Index" });
                }

                if (user.Role == AppConstants.RoleDriver)
                {
                    var driver = await _context.Drivers.AsNoTracking()
                        .Where(d => d.UserId == user.Id)
                        .Select(d => new
                        {
                            d.Id,
                            d.DriverName,
                            d.Vehicle,
                            d.Phone,
                            d.Station,
                            d.Status,
                            d.LicenseNo
                        })
                        .FirstOrDefaultAsync();

                    if (driver == null)
                    {
                        var driverEntity = new Driver
                        {
                            UserId = user.Id,
                            DriverName = user.Username ?? "Unknown",
                            Vehicle = "N/A",
                            Phone = "N/A",
                            LicenseNo = "N/A",
                            Station = "Bệnh viện Columbia Asia",
                            Status = AppConstants.StatusOnline
                        };
                        _context.Drivers.Add(driverEntity);
                        await _context.SaveChangesAsync();
                        driver = new
                        {
                            driverEntity.Id,
                            driverEntity.DriverName,
                            driverEntity.Vehicle,
                            driverEntity.Phone,
                            driverEntity.Station,
                            driverEntity.Status,
                            driverEntity.LicenseNo
                        };
                    }

                    string station = string.IsNullOrEmpty(driver.Station) ? "Bệnh viện Columbia Asia" : driver.Station;

                    var coords = (!string.IsNullOrEmpty(station) && StationCoords.TryGetValue(station, out var c))
                        ? c
                        : (10.80165, 106.69796);

                    HttpContext.Session.SetString(AppConstants.SessionUsername, user.Username ?? "N/A");
                    HttpContext.Session.SetInt32(AppConstants.SessionRole, AppConstants.RoleValueDriver);
                    HttpContext.Session.SetString(AppConstants.SessionStaff, user.Username ?? "N/A");
                    HttpContext.Session.SetString(AppConstants.SessionHospitalName, station ?? "N/A");
                    HttpContext.Session.SetString(AppConstants.SessionVehicle, driver.Vehicle ?? "N/A");
                    HttpContext.Session.SetString(AppConstants.SessionPhone, driver.Phone ?? "N/A");
                    HttpContext.Session.SetString(AppConstants.SessionShiftStart, DateTime.UtcNow.ToString("HH:mm dd/MM/yyyy"));

                    HttpContext.Session.SetString(AppConstants.SessionStationLat, coords.Item1.ToString(CultureInfo.InvariantCulture));
                    HttpContext.Session.SetString(AppConstants.SessionStationLng, coords.Item2.ToString(CultureInfo.InvariantCulture));

                    return Json(new { success = true, redirectUrl = "/Home/Map" });
                }

                return Json(new { success = false, message = "Không hỗ trợ role này" });
            }
            catch (Exception ex)
            {
                var innerExceptionMessage = ex.InnerException != null ? ex.InnerException.Message : ex.Message;
                Console.WriteLine($"Error during login process: {innerExceptionMessage}");
                return Json(new { success = false, message = "Lỗi hệ thống: " + innerExceptionMessage });
            }
        }

        private void SetAdminSession(string username, string staffName)
        {
            HttpContext.Session.SetInt32(AppConstants.SessionRole, AppConstants.RoleValueAdmin);
            HttpContext.Session.SetString(AppConstants.SessionStaff, staffName ?? "Admin");
            HttpContext.Session.SetString(AppConstants.SessionUsername, username ?? "admin");
        }

        [HttpGet]
        public IActionResult GetDriverInfo()
        {
            var staff = HttpContext.Session.GetString(AppConstants.SessionStaff) ?? HttpContext.Session.GetString(AppConstants.SessionUsername);
            if (string.IsNullOrEmpty(staff))
                return Json(new { success = false });

            return Json(new
            {
                success = true,
                driverName = staff,
                vehicle = HttpContext.Session.GetString(AppConstants.SessionVehicle) ?? "N/A",
                phone = HttpContext.Session.GetString(AppConstants.SessionPhone) ?? "Chưa nhập",
                shiftStart = HttpContext.Session.GetString(AppConstants.SessionShiftStart) ?? "N/A",
                station = HttpContext.Session.GetString(AppConstants.SessionHospitalName) ?? "N/A"
            });
        }

        public IActionResult Logout()
        {
            HttpContext.Session.Clear();
            return RedirectToAction("Login");
        }
    }
}
