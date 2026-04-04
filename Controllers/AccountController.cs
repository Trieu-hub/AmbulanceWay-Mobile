using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Http;
using Microsoft.EntityFrameworkCore;
using AmbulanceWay.Data;
using AmbulanceWay.Models;

namespace AmbulanceWay.Controllers
{
    public class AccountController : Controller
    {
        private readonly AmbulanceWayDbContext _context;

        public AccountController(AmbulanceWayDbContext context)
        {
            _context = context;
        }

        // --- 1. HIỂN THỊ TRANG ĐĂNG NHẬP (Fix lỗi 405) ---
        [HttpGet]
        public IActionResult Login()
        {
            // Nếu đã đăng nhập rồi thì chuyển hướng thẳng vào trong, không hiện trang login nữa
            if (HttpContext.Session.GetString("USERNAME") != null)
            {
                return RedirectToAction("Index", "Home");
            }
            return View();
        }

        // --- 2. XỬ LÝ LOGIC ĐĂNG NHẬP ---
        [HttpPost]
        [ValidateAntiForgeryToken] // Bảo mật chống tấn công giả mạo
        public async Task<IActionResult> Login(string username, string password)
        {
            if (string.IsNullOrEmpty(username) || string.IsNullOrEmpty(password))
                return Json(new { success = false, message = "Vui lòng nhập đầy đủ tài khoản và mật khẩu" });

            var user = await _context.Users
                .FirstOrDefaultAsync(x => x.Username == username);

            // Lưu ý: Trong thực tế nên dùng BCrypt để so sánh HashPassword thay vì so sánh chuỗi trực tiếp
            if (user == null || user.PasswordHash != password)
                return Json(new { success = false, message = "Tài khoản hoặc mật khẩu không chính xác" });

            if (user.Status != "ACTIVE")
                return Json(new { success = false, message = "Tài khoản đang bị tạm khóa" });

            // Lưu thông tin vào Session
            HttpContext.Session.SetString("USERNAME", user.Username);
            HttpContext.Session.SetString("ROLE", user.Role ?? "user");

            // Điều hướng dựa trên quyền
            string redirectUrl = (user.Role?.ToLower() == "admin")
                ? Url.Action("Index", "Admin")!
                : Url.Action("Index", "Home")!;

            return Json(new { success = true, redirectUrl });
        }

        // --- 3. ĐĂNG NHẬP CA TRỰC (AJAX) ---
        [HttpPost]
        public IActionResult LoginAjax([FromBody] DutyLoginModel model)
        {
            if (model == null ||
                string.IsNullOrWhiteSpace(model.HospitalName) ||
                string.IsNullOrWhiteSpace(model.StaffName))
            {
                return Json(new { success = false, message = "Thiếu thông tin ca trực" });
            }

            HttpContext.Session.SetString("HOSPITAL", model.HospitalName);
            HttpContext.Session.SetString("STAFF", model.StaffName);
            HttpContext.Session.SetString("VEHICLE", model.VehicleNo ?? "");
            HttpContext.Session.SetString("SHIFT_START", DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"));

            return Json(new { success = true });
        }

        // --- 4. LẤY THÔNG TIN TÀI XẾ ---
        [HttpGet]
        public IActionResult GetDriverInfo()
        {
            var staff = HttpContext.Session.GetString("STAFF");
            if (string.IsNullOrEmpty(staff)) return NotFound();

            return Json(new
            {
                staff = staff,
                hospital = HttpContext.Session.GetString("HOSPITAL"),
                vehicle = HttpContext.Session.GetString("VEHICLE")
            });
        }

        // --- 5. ĐĂNG XUẤT ---
        [HttpGet] // Thêm HttpGet để link <a> Logout hoạt động bình thường
        public IActionResult Logout()
        {
            HttpContext.Session.Clear();
            return RedirectToAction("Login", "Account");
        }
    }

    // Model cho Login AJAX
    public class DutyLoginModel
    {
        public string HospitalName { get; set; } = null!;
        public string StaffName { get; set; } = null!;
        public string VehicleNo { get; set; } = null!;
    }
}