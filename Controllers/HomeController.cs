using System.Diagnostics;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using AmbulanceWay.Models;
using AmbulanceWay.Data;

namespace AmbulanceWay.Controllers
{
    public class HomeController : Controller
    {
        private readonly AmbulanceWayDbContext _context;

        public HomeController(AmbulanceWayDbContext context)
        {
            _context = context;
        }

        // Helper check session để code gọn hơn
        private string? CurrentUser => HttpContext.Session.GetString("USERNAME");

        public async Task<IActionResult> Index()
        {
            if (string.IsNullOrEmpty(CurrentUser))
                return RedirectToAction("Login", "Account");

            // Lấy danh sách chuyến đi, sắp xếp mới nhất
            var trips = await _context.AmbulanceTrips
                .AsNoTracking()
                .OrderByDescending(t => t.Id)
                .Take(100)
                .ToListAsync();

            return View(trips);
        }

        public IActionResult Map()
        {
            if (string.IsNullOrEmpty(CurrentUser))
                return RedirectToAction("Login", "Account");

            return View();
        }

        [HttpPost]
        public async Task<IActionResult> Login([FromBody] LoginRequest model) 
        {
            if (model == null || string.IsNullOrEmpty(model.Username))
                return Json(new { success = false, message = "Vui lòng nhập tên tài khoản!" });

            // 1. Tìm User (Dùng User? để hết báo lỗi CS8600)
            User? user = await _context.Users
                .FirstOrDefaultAsync(x => x.Username == model.Username);

            // 2. Nếu chưa có thì tự động tạo tài khoản (Role: STAFF theo SQL của bạn)
            if (user == null)
            {
                user = new User
                {
                    Username = model.Username,
                    PasswordHash = "default", // Cột này sẽ tự ánh xạ vào cột 'Password' trong SQL
                    Role = "STAFF",           // Khớp với DEFAULT 'STAFF' trong SQL của bạn
                    Status = "ACTIVE",
                    IsOnline = true,
                    CreatedAt = DateTime.Now 
                };

                _context.Users.Add(user);
                await _context.SaveChangesAsync();
            }

            // 3. Kiểm tra trạng thái
            if (user.Status != "ACTIVE")
                return Json(new { success = false, message = "Tài khoản đang bị khóa!" });

            // 4. Lưu Session (Lưu ý: Role là chuỗi "ADMIN" hoặc "STAFF")
            HttpContext.Session.SetString("USERNAME", user.Username);
            HttpContext.Session.SetString("ROLE", user.Role);

            if (user.Role == "STAFF") // Nếu là tài xế
            {
                HttpContext.Session.SetString("STATION", model.Station ?? "N/A");
                HttpContext.Session.SetString("VEHICLE", model.Vehicle ?? "N/A");
                HttpContext.Session.SetString("SHIFT_START", DateTime.Now.ToString("HH:mm dd/MM/yyyy"));
            }

            // 5. Điều hướng dựa trên Role chuỗi
            string? redirectUrl = user.Role.ToUpper() == "ADMIN"
                ? Url.Action("Index", "Admin")
                : Url.Action("Index", "Home");

            return Json(new { success = true, redirectUrl });
        }

        [HttpPost]
        public IActionResult EndShift()
        {
            HttpContext.Session.Clear();
            return Json(new { success = true });
        }

        [HttpGet]
        public async Task<IActionResult> GetNearestHospital(double lat, double lng)
        {
            // Tối ưu truy vấn: Chỉ lấy những cột cần thiết
            var hospitals = await _context.Hospitals
                .AsNoTracking()
                .ToListAsync();
            
            if (!hospitals.Any()) return Json(null);

            var nearest = hospitals.Select(h => new
                {
                    h.Id,
                    h.Name,
                    h.Address,
                    Distance = 6371 * Math.Acos(
                        Math.Cos(Math.PI * lat / 180) *
                        Math.Cos(Math.PI * (double)h.Lat / 180) *
                        Math.Cos(Math.PI * ((double)h.Lng - lng) / 180) +
                        Math.Sin(Math.PI * lat / 180) *
                        Math.Sin(Math.PI * (double)h.Lat / 180)
                    )
                })
                .OrderBy(h => h.Distance)
                .FirstOrDefault();

            return Json(nearest);
        }

        [ResponseCache(Duration = 0, Location = ResponseCacheLocation.None, NoStore = true)]
        public IActionResult Error()
        {
            return View(new ErrorViewModel { RequestId = Activity.Current?.Id ?? HttpContext.TraceIdentifier });
        }
    }

    public class LoginRequest
    {
        public string? Username { get; set; }
        public string? Password { get; set; }
        public string? Station { get; set; }
        public string? Vehicle { get; set; }
    }
}