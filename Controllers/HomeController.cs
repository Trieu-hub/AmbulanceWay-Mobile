using System.Diagnostics;
using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using AmbulanceWay.Constants; // Import AppConstants
using AmbulanceWay.Data;
using AmbulanceWay.Models;
using AmbulanceWay.Controllers.Api;



namespace AmbulanceWay.Controllers
{
    public class HomeController : Controller
    {
        private readonly AmbulanceWayDbContext _context;
        private readonly IConfiguration _configuration;

        public HomeController(AmbulanceWayDbContext context, IConfiguration configuration)
        {
            _context = context;
            _configuration = configuration;
        }

        // Helper check session để code gọn hơn
        private string? CurrentUser => HttpContext.Session.GetString(AppConstants.SessionUsername); // Sử dụng hằng số

        public IActionResult Index()
        {
            if (string.IsNullOrEmpty(CurrentUser))
                return RedirectToAction("Login", "Account");

            var role = HttpContext.Session.GetInt32(AppConstants.SessionRole);

            if (role == AppConstants.RoleValueAdmin)
                return RedirectToAction("Index", "Admin");

            if (role == AppConstants.RoleValueDriver)
                return RedirectToAction("Map", "Home");

            if (role == AppConstants.RoleValueHospital)
                return RedirectToAction("Dashboard", "HospitalPortalMvc");
            
            if (role == AppConstants.RoleValuePatient)
                return RedirectToAction("Sos", "Patient");

            return RedirectToAction("Login", "Account");
        }

        public IActionResult Map()
        {
            if (string.IsNullOrEmpty(CurrentUser))
                return RedirectToAction("Login", "Account");

            // Kiểm tra quyền: Chỉ tài xế (ROLE = 2) mới được vào trang này
            var role = HttpContext.Session.GetInt32(AppConstants.SessionRole);
            if (role != AppConstants.RoleValueDriver && role != AppConstants.RoleValueAdmin) // Cho phép cả Admin vào xem để test
                return RedirectToAction("Index");

            return View();
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
            var hospitals = await _context.Hospitals
                .AsNoTracking()
                .Where(h => h.IsActive)
                .ToListAsync();

            if (!hospitals.Any()) return Json(null);

            // Bug #3 fix: Dùng Haversine chuẩn (giống SosController) thay vì spherical law of cosines sai
            var nearest = hospitals.Select(h => new
            {
                h.Id,
                h.Name,
                h.Address,
                Lat = h.Lat,
                Lng = h.Lng,
                Distance = HaversineKm(lat, lng, (double)h.Lat, (double)h.Lng)
            })
                .OrderBy(h => h.Distance)
                .FirstOrDefault();

            return Json(nearest);
        }

        private static double HaversineKm(double lat1, double lon1, double lat2, double lon2)
        {
            const double R = 6371;
            double dLat = (lat2 - lat1) * Math.PI / 180.0;
            double dLon = (lon2 - lon1) * Math.PI / 180.0;
            double a = Math.Sin(dLat / 2) * Math.Sin(dLat / 2) +
                       Math.Cos(lat1 * Math.PI / 180.0) * Math.Cos(lat2 * Math.PI / 180.0) *
                       Math.Sin(dLon / 2) * Math.Sin(dLon / 2);
            return R * 2 * Math.Atan2(Math.Sqrt(a), Math.Sqrt(1 - a));
        }
[HttpPost]
        [Route("Home/SaveTripApi")] // Đổi route để tránh xung đột với TripsController (AmbulanceTripApiController)
        public async Task<IActionResult> SaveTrip([FromBody] TripSaveRequest model)
        {
            try
            {
                // Lấy thông tin từ Session (đã được lưu lúc Login)
                var staffName = HttpContext.Session.GetString(AppConstants.SessionUsername) ?? "N/A";
                var vehicle = HttpContext.Session.GetString(AppConstants.SessionVehicle) ?? "N/A";
                var shiftStartStr = HttpContext.Session.GetString(AppConstants.SessionShiftStart);
                DateTime.TryParse(shiftStartStr, out DateTime shiftStart);

                var newTrip = new AmbulanceTrip
                {
                    StaffName = staffName,
                    VehicleNo = vehicle,
                    Hospital = model.HospitalName,
                    HospitalAddress = model.HospitalAddress,
                    HospitalLat = (decimal)model.HospitalLat,
                    HospitalLng = (decimal)model.HospitalLng,

                    IncidentAddress = model.PatientAddress,
                    IncidentLat = (decimal)model.PatientLat,
                    IncidentLng = (decimal)model.PatientLng,

                    DistanceKm = (decimal)model.DistanceKm,
                    EstimatedMinutes = model.Duration,

                    ShiftStart = shiftStart == DateTime.MinValue ? DateTime.UtcNow : shiftStart, // Sử dụng UtcNow
                    Status = AppConstants.CaseStatusCompleted,
                    CreatedAt = DateTime.UtcNow // Sử dụng UtcNow
                };

                _context.AmbulanceTrips.Add(newTrip);
                // === LƯU VÀO TRIP HISTORY (kèm rating nếu có) ===
                var tripHistory = new TripHistory
                {   // "COMPLETED" có thể là hằng số
                    DriverName = staffName,
                    VehicleNo = vehicle,
                    HospitalName = model.HospitalName,
                    HospitalAddress = model.HospitalAddress,
                    HospitalLat = (decimal)model.HospitalLat,
                    HospitalLng = (decimal)model.HospitalLng,
                    PatientAddress = model.PatientAddress,
                    PatientLat = (decimal)model.PatientLat,
                    PatientLng = (decimal)model.PatientLng,
                    DistanceKm = (decimal)Math.Round(model.DistanceKm, 2),
                    DurationMinutes = model.Duration,
                    TripStatus = AppConstants.CaseStatusCompleted, // Sử dụng hằng số
                    CreatedAt = shiftStart == DateTime.MinValue ? DateTime.UtcNow.AddMinutes(-model.Duration) : shiftStart,
                    CompletedAt = DateTime.UtcNow,

                    OverallRating = model.OverallRating,
                    TimeRating = model.TimeRating,
                    AttitudeRating = model.AttitudeRating,
                    VehicleRating = model.VehicleRating,
                    SituationRating = model.SituationRating,
                    DriverNote = model.DriverNote
                };

                _context.TripHistories.Add(tripHistory);

                await _context.SaveChangesAsync();

                return Ok(new { success = true });
            }
            catch (Exception ex)
            {
                return BadRequest(new { message = ex.InnerException?.Message ?? ex.Message });
            }
        }

        // Class này phải khớp với dữ liệu Javascript gửi lên
        public class TripSaveRequest
        {
            public string HospitalName { get; set; } = "";
            public string HospitalAddress { get; set; } = "";
            public double HospitalLat { get; set; }
            public double HospitalLng { get; set; }

            public string PatientAddress { get; set; } = "";
            public double PatientLat { get; set; }
            public double PatientLng { get; set; }

            public double DistanceKm { get; set; }
            public int Duration { get; set; }
            public string Status { get; set; } = "COMPLETED";

            // Rating sau chuyến (tùy chọn)
            public int? OverallRating { get; set; }
            public int? TimeRating { get; set; }
            public int? AttitudeRating { get; set; }
            public int? VehicleRating { get; set; }
            public int? SituationRating { get; set; }
            public string? DriverNote { get; set; }
        }
        [HttpGet]
        public async Task<IActionResult> GetDriverInfo()
        {
            // Ưu tiên lấy Username chính xác từ SessionRole
            var username = HttpContext.Session.GetString(AppConstants.SessionUsername);
            if (string.IsNullOrEmpty(username)) {
                username = HttpContext.Session.GetString(AppConstants.SessionStaff);
            }

            if (string.IsNullOrEmpty(username))
                return Json(new { success = false, message = "Chưa đăng nhập" });

            // Ưu tiên lấy từ Session (STATION từ HomeController, HOSPITAL từ AccountController)
            var station = HttpContext.Session.GetString(AppConstants.SessionStation) ?? HttpContext.Session.GetString(AppConstants.SessionHospitalName) ?? "N/A"; // TODO: "N/A" có thể là hằng số
            var vehicle = HttpContext.Session.GetString(AppConstants.SessionVehicle) ?? "N/A"; // TODO: "N/A" có thể là hằng số
            var shiftStart = HttpContext.Session.GetString(AppConstants.SessionShiftStart) ?? "N/A"; // TODO: "N/A" có thể là hằng số
            var stationLat = HttpContext.Session.GetString(AppConstants.SessionStationLat) ?? "10.80165"; // TODO: Nên đưa vào cấu hình
            var stationLng = HttpContext.Session.GetString(AppConstants.SessionStationLng) ?? "106.69796";

                // driver phone (from Drivers table if exists)
                var phone = await _context.Drivers
                    .Include(d => d.User)
                    .OrderBy(d => d.Id)
                    .Where(d => d.User.Username == username)
                    .Select(d => d.Phone)
                    .FirstOrDefaultAsync();

                return Json(new
            {
                success = true,
                driverName = username, // Đây chính là Username dùng để đăng ký SignalR
                station = station,
                vehicle = vehicle,
                phone = phone,
                shiftStart = shiftStart,
                stationLat = stationLat,
                stationLng = stationLng
            });
        }

        // GET /Home/DriverToken
        // Trang bản đồ tài xế (web) đổi phiên đăng nhập lấy JWT để dùng chung các API với app mobile:
        // /api/duty/*, /api/mobile/driver/* (ca đang chờ, khôi phục ca đang làm, chọn bệnh viện, lịch sử).
        [HttpGet]
        [ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
        public async Task<IActionResult> DriverToken()
        {
            var username = CurrentUser;
            var role = HttpContext.Session.GetInt32(AppConstants.SessionRole);
            if (string.IsNullOrEmpty(username) || role != AppConstants.RoleValueDriver)
                return StatusCode(StatusCodes.Status403Forbidden, new { message = "Trang này dành cho tài khoản tài xế." });

            var user = await _context.Users.AsNoTracking().FirstOrDefaultAsync(u => u.Username == username);
            if (user == null || user.Status != AppConstants.StatusActive)
                return StatusCode(StatusCodes.Status403Forbidden, new { message = "Tài khoản tài xế không còn hoạt động." });

            var token = MobileJwt.Create(_configuration, new[]
            {
                new Claim(ClaimTypes.Name, user.Username),
                new Claim(ClaimTypes.Role, AppConstants.RoleDriver),
                new Claim("UserId", user.Id.ToString()),
                new Claim("Status", user.Status ?? AppConstants.StatusActive)
            }, TimeSpan.FromHours(12));

            return Json(new { token, username = user.Username });
        }

        [ResponseCache(Duration = 0, Location = ResponseCacheLocation.None, NoStore = true)]
        public IActionResult Error()
        {
            return View(new ErrorViewModel { RequestId = Activity.Current?.Id ?? HttpContext.TraceIdentifier });
        }
    }
}