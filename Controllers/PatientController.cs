using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Http;
using AmbulanceWay.Data;
using Microsoft.EntityFrameworkCore;
using AmbulanceWay.Constants;
using AmbulanceWay.Controllers.Api;
using System;
using System.Security.Claims;
using System.Threading.Tasks;

namespace AmbulanceWay.Controllers
{
    public class PatientController : Controller
    {
        private const string SessionProfileId = "PATIENT_PROFILE_ID";
        private const string SessionPatientName = "PATIENT_NAME";

        private readonly AmbulanceWayDbContext _context;
        private readonly IConfiguration _configuration;

        public PatientController(AmbulanceWayDbContext context, IConfiguration configuration)
        {
            _context = context;
            _configuration = configuration;
        }

        private int? CurrentProfileId
        {
            get
            {
                var role = HttpContext.Session.GetInt32(AppConstants.SessionRole);
                var profileId = HttpContext.Session.GetInt32(SessionProfileId);
                return role == AppConstants.RoleValuePatient && profileId > 0 ? profileId : null;
            }
        }

        public IActionResult Index() => RedirectToAction(nameof(Register));

        // Đăng nhập / tạo hồ sơ bằng SĐT + OTP (gọi /api/patientauth/* giống app mobile)
        [HttpGet]
        public IActionResult Register()
        {
            if (CurrentProfileId != null) return RedirectToAction(nameof(Sos));
            return View("~/Views/Account/PatientRegister.cshtml");
        }

        // POST /Patient/OpenSession  (Authorization: Bearer <token từ /api/patientauth/verify-otp>)
        // Chỉ mở phiên web cho hồ sơ đã xác thực OTP. Trước đây trang web gửi thẳng form hồ sơ lên
        // và máy chủ mở phiên cho bất kỳ SĐT nào đã tồn tại, tức là ai cũng vào được hồ sơ của người khác.
        [HttpPost]
        [Authorize(Roles = AppConstants.RolePatient)]
        public async Task<IActionResult> OpenSession()
        {
            var profileId = MobileJwt.GetPatientProfileId(User);
            var profile = profileId == null
                ? null
                : await _context.PatientProfiles.AsNoTracking().FirstOrDefaultAsync(p => p.Id == profileId.Value);

            if (profile == null || !profile.IsOtpVerified)
                return Unauthorized(new { message = "Phiên xác thực không hợp lệ, vui lòng lấy mã OTP mới." });

            // Bỏ phiên cũ (ví dụ tài xế/quản trị đăng nhập trên cùng trình duyệt) để không lẫn vai trò
            HttpContext.Session.Clear();
            HttpContext.Session.SetInt32(SessionProfileId, profile.Id);
            HttpContext.Session.SetString(SessionPatientName, profile.FullName ?? "");
            HttpContext.Session.SetInt32(AppConstants.SessionRole, AppConstants.RoleValuePatient);

            return Json(new { success = true, redirectUrl = Url.Action(nameof(Sos)) });
        }

        // GET /Patient/Token
        // Trang SOS (web) lấy JWT của hồ sơ trong phiên để gọi /api/mobile/patient/* như app mobile
        // (khôi phục ca đang theo dõi khi tải lại trang, gửi đánh giá).
        [HttpGet]
        [ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
        public async Task<IActionResult> Token()
        {
            var profileId = CurrentProfileId;
            if (profileId == null) return Unauthorized(new { message = "Phiên đăng nhập đã hết, vui lòng đăng nhập lại." });

            var profile = await _context.PatientProfiles.AsNoTracking().FirstOrDefaultAsync(p => p.Id == profileId.Value);
            if (profile == null)
            {
                HttpContext.Session.Clear();
                return Unauthorized(new { message = "Không tìm thấy hồ sơ, vui lòng đăng nhập lại." });
            }

            var token = MobileJwt.Create(_configuration, new[]
            {
                new Claim(ClaimTypes.Name, profile.PhoneNumber),
                new Claim(ClaimTypes.Role, AppConstants.RolePatient),
                new Claim(MobileJwt.PatientProfileIdClaim, profile.Id.ToString())
            }, TimeSpan.FromHours(12));

            return Json(new { token, profileId = profile.Id, fullName = profile.FullName });
        }

        [HttpGet]
        public IActionResult Sos()
        {
            if (CurrentProfileId == null) return RedirectToAction(nameof(Register));
            return View("~/Views/Account/Sos.cshtml");
        }

        [HttpGet]
        public IActionResult Logout()
        {
            HttpContext.Session.Clear();
            return RedirectToAction(nameof(Register));
        }
    }
}
