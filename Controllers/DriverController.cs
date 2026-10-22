using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using AmbulanceWay.Models;
using AmbulanceWay.Data;
using System.Linq;
using Microsoft.AspNetCore.Http;
using BCrypt.Net;
using AmbulanceWay.Constants;

namespace AmbulanceWay.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class DriverController : Controller
    {
        private readonly AmbulanceWayDbContext _context;

        public DriverController(AmbulanceWayDbContext context)
        {
            _context = context;
        }

        public IActionResult Index()
        {
            var data = _context.Drivers.ToList();
            return View(data);
        }

        [HttpGet]
        public JsonResult GetDrivers()
        {
            var list = _context.Drivers
                .Select(d => new
                {
                    id = d.Id,
                    driverName = d.DriverName,
                    vehicle = d.Vehicle,
                    station = d.Station
                }).ToList();
            return Json(list);
        }

        [HttpPost]
        public async Task<IActionResult> AddDriver([FromBody] RegisterDriverModel model)
        {
            // Nếu JS chỉ gửi DriverName, Vehicle, Station thì ta phải xử lý Username tự động
            if (model == null) return BadRequest("Dữ liệu trống");

            // Tạo Username tự động nếu JS không gửi (để tránh lỗi BadRequest)
            if (string.IsNullOrEmpty(model.Username))
                model.Username = "driver_" + DateTime.UtcNow.Ticks.ToString().Substring(10);
            
            var strategy = _context.Database.CreateExecutionStrategy();
            return await strategy.ExecuteAsync<IActionResult>(async () =>
            {
                await using var transaction = await _context.Database.BeginTransactionAsync();
                try
                {
                    // 1. Tạo User
                    var newUser = new User // Đã hash mật khẩu
                    {
                        Username = model.Username,
                        Password = BCrypt.Net.BCrypt.HashPassword(model.Password ?? "123"),
                        Role = AppConstants.RoleDriver, 
                        Status = AppConstants.StatusActive,
                        IsOnline = false,
                        CreatedAt = DateTime.UtcNow // Sử dụng UtcNow
                    };
                    _context.Users.Add(newUser);
                    await _context.SaveChangesAsync();

                    // 2. Tạo Driver
                    var newDriver = new Driver
                    {
                        DriverName = model.FullName ?? model.Username, 
                        Vehicle = model.Vehicle,
                        Phone = model.Phone ?? "000",
                        LicenseNo = model.LicenseNo ?? "N/A", // TODO: "N/A" có thể là hằng số
                        Station = model.Station ?? "Trạm Trung Tâm", // TODO: Nên dùng hằng số hoặc lấy từ cấu hình
                        UserId = newUser.Id
                    };
                    _context.Drivers.Add(newDriver);
                    await _context.SaveChangesAsync();

                    await transaction.CommitAsync();

                    // QUAN TRỌNG: Cấp session để khi chuyển qua Map không bị đuổi ra
                    HttpContext.Session.SetString(AppConstants.SessionUsername, newUser.Username);
                    HttpContext.Session.SetInt32(AppConstants.SessionRole, AppConstants.RoleValueDriver); 

                    return Ok(new { message = "Thành công" });
                }
                catch (Exception ex)
                {
                    await transaction.RollbackAsync();
                    return BadRequest("Lỗi: " + ex.Message);
                }
            });
        }
        [HttpPost]
        public IActionResult Update(Driver driver)
        {
            if (driver == null) return BadRequest();
            var existing = _context.Drivers.Find(driver.Id);
            if (existing == null) return NotFound();

            existing.DriverName = driver.DriverName;
            existing.Phone = driver.Phone;
            existing.Vehicle = driver.Vehicle;
            existing.Station = driver.Station;
            existing.LicenseNo = driver.LicenseNo;

            _context.SaveChanges();
            return RedirectToAction("Profile", new { id = driver.Id });
        }

        [HttpGet("me")]
        public async Task<IActionResult> GetMe()
        {
            // Bug #1 fix: Dùng Session thay vì JWT claim
            var username = HttpContext.Session.GetString(AppConstants.SessionUsername); // Sử dụng hằng số
            if (string.IsNullOrEmpty(username))
                return Unauthorized(new { message = "Chưa đăng nhập" });

            var driver = await _context.Drivers
                .Include(d => d.User)
                .FirstOrDefaultAsync(d => d.User.Username == username);

            if (driver == null) return NotFound(new { message = "Driver not found" });

            return Ok(new {
                id = driver.Id,
                driverName = driver.DriverName,
                vehicle = driver.Vehicle,
                station = driver.Station,
                phone = driver.Phone,
                status = driver.Status
            });
        }

        [HttpPost("status")]
        public async Task<IActionResult> UpdateStatus([FromBody] UpdateStatusRequest request)
        {
            // Bug #1 fix: Dùng Session thay vì JWT claim
            var username = HttpContext.Session.GetString(AppConstants.SessionUsername); // Sử dụng hằng số
            if (string.IsNullOrEmpty(username))
                return Unauthorized(new { message = "Chưa đăng nhập" });

            var driver = await _context.Drivers
                .Include(d => d.User)
                .FirstOrDefaultAsync(d => d.User.Username == username);
            if (driver == null) return NotFound(new { message = "Driver not found" });

            if (string.IsNullOrEmpty(request.Status) || (request.Status != AppConstants.StatusOnline && request.Status != AppConstants.StatusOffline)) // Nên dùng hằng số
                return BadRequest(new { message = "Invalid status" });

            driver.Status = request.Status;
            await _context.SaveChangesAsync();

            return Ok(new { success = true, status = driver.Status });
        }

        public IActionResult Profile(int id)
        { // Role 1 có thể là hằng số
            var driver = _context.Drivers.Find(id); // Role 1 có thể là hằng số
            if (driver == null) return NotFound();

            var role = HttpContext.Session.GetInt32(AppConstants.SessionRole);
            if (role != null && role == 1) // 1 is Admin
            {
                return View("Edit", driver);
            }
            return View("Profile", driver);
        }

        public class RegisterDriverModel
        {
            public string Username { get; set; } = "";
            public string Password { get; set; } = "123";
            public string FullName { get; set; } = "";
            public string Vehicle { get; set; } = "";
            public string Phone { get; set; } = "";
            public string LicenseNo { get; set; } = "";
            public string Station { get; set; } = "";
        }

        public class UpdateStatusRequest
        {
            public string Status { get; set; } = "";
        }
    }
}
