using Microsoft.AspNetCore.Mvc;
using AmbulanceWay.Data;
using AmbulanceWay.Hubs;
using AmbulanceWay.Models;
using Microsoft.AspNetCore.SignalR;
using AmbulanceWay.Constants; // Import AppConstants
using BCrypt.Net;
using Microsoft.EntityFrameworkCore;
 
namespace AmbulanceWay.Controllers
{
    /// <summary>
    /// Controller cho portal bệnh viện: đăng nhập, cập nhật giường trống,
    /// xem và xử lý các tín hiệu ca cấp cứu đang đến.
    /// Route prefix: /api/HospitalPortal
    /// </summary>
    [ApiController]
    [Route("api/[controller]")]
    public class HospitalPortalController : ControllerBase
    {
        private readonly AmbulanceWayDbContext _context;
        private readonly IHubContext<AmbulanceHub> _hub;

 
        public HospitalPortalController(AmbulanceWayDbContext context, IHubContext<AmbulanceHub> hub)
        {
            _context = context;
            _hub = hub;
        }
 
        // ===================================================================
        // POST /api/HospitalPortal/login
        // ===================================================================
        public class HospitalLoginRequest
        {
            public string Username { get; set; } = null!;
            public string Password { get; set; } = null!;
        }
 
        [HttpPost("login")]
        public async Task<IActionResult> Login([FromBody] HospitalLoginRequest req)
        {
            if (req == null) return BadRequest(new { message = "Dữ liệu trống" });
 
            var user = await _context.HospitalUsers
                .AsNoTracking()
                .Include(u => u.Hospital)
                .FirstOrDefaultAsync(u => u.Username == req.Username && u.Status == AppConstants.StatusActive);
 
            if (user == null)
                return Unauthorized(new { success = false, message = "Tài khoản hoặc mật khẩu không đúng" });
            
            // Xác minh mật khẩu đã hash
            if (!BCrypt.Net.BCrypt.Verify(req.Password, user.Password)) // Verify mật khẩu
                return Unauthorized(new { success = false, message = "Tài khoản hoặc mật khẩu không đúng" });
 
            // Lưu session (giống flow admin/driver hiện tại)
            HttpContext.Session.SetInt32("HOSPITAL_USER_ID", user.Id); // Có thể tạo hằng số cho key này
            HttpContext.Session.SetInt32(AppConstants.SessionHospitalId, user.HospitalId); // Sử dụng hằng số
            HttpContext.Session.SetInt32(AppConstants.SessionRole, AppConstants.RoleValueHospital);
            HttpContext.Session.SetString(AppConstants.SessionHospitalName, user.Hospital?.Name ?? ""); // Sử dụng hằng số
            HttpContext.Session.SetString(AppConstants.SessionHospitalUsername, user.Username); // Sử dụng hằng số
 
            return Ok(new
            {
                success = true,
                hospitalId = user.HospitalId,
                hospitalName = user.Hospital?.Name,
                fullName = user.FullName,
                redirectUrl = "/HospitalPortal/Dashboard"
            });
        }
 
        // ===================================================================
        // GET /api/HospitalPortal/me  — Lấy thông tin BV từ session
        // ===================================================================
        [HttpGet("me")]
        public async Task<IActionResult> GetMe()
        {
            var hospitalId = HttpContext.Session.GetInt32(AppConstants.SessionHospitalId); // Sử dụng hằng số
            if (hospitalId == null) return Unauthorized(new { message = "Chưa đăng nhập" });
 
            var hospital = await _context.Hospitals.FindAsync(hospitalId.Value);
            if (hospital == null) return NotFound();
 
            return Ok(new
            {
                hospitalId = hospital.Id,
                name = hospital.Name,
                address = hospital.Address,
                totalBeds = hospital.TotalEmergencyBeds,
                availableBeds = hospital.AvailableEmergencyBeds,
                receptionStatus = hospital.ReceptionStatus,
                statusNote = hospital.StatusNote,
                statusUpdatedAt = hospital.StatusUpdatedAt
            });
        }
 
        // ===================================================================
        // PUT /api/HospitalPortal/capacity  — BV cập nhật giường trống + trạng thái
        // ===================================================================
        public class UpdateCapacityRequest
        {
            public int AvailableEmergencyBeds { get; set; }
            /// <summary>OPEN / FULL / CLOSED</summary>
            public string ReceptionStatus { get; set; } = "OPEN";
            public string? StatusNote { get; set; }
        }
 
        [HttpPut("capacity")]
        public async Task<IActionResult> UpdateCapacity([FromBody] UpdateCapacityRequest req)
        {
            var hospitalId = HttpContext.Session.GetInt32(AppConstants.SessionHospitalId); // Sử dụng hằng số
            if (hospitalId == null) return Unauthorized(new { message = "Chưa đăng nhập" });
 
            var hospital = await _context.Hospitals.FindAsync(hospitalId.Value);
            if (hospital == null) return NotFound();
 
            hospital.AvailableEmergencyBeds = req.AvailableEmergencyBeds;
            hospital.ReceptionStatus = req.ReceptionStatus;
            hospital.StatusNote = req.StatusNote; // "OPEN" có thể là hằng số
            hospital.StatusUpdatedAt = DateTime.UtcNow; // Sử dụng UtcNow
 
            await _context.SaveChangesAsync();
 
            // Broadcast trạng thái mới cho admin và tài xế
            await _hub.Clients.Groups(AppConstants.RoleAdminsGroup, AppConstants.RoleDriversGroup).SendAsync(AppConstants.SignalRHospitalCapacityUpdated, new
            {
                hospitalId = hospital.Id,
                hospitalName = hospital.Name,
                availableBeds = hospital.AvailableEmergencyBeds, // "Admins", "Drivers" có thể là hằng số
                receptionStatus = hospital.ReceptionStatus,
                statusNote = hospital.StatusNote,
                updatedAt = hospital.StatusUpdatedAt
            });
 
            return Ok(new { success = true, message = "Cập nhật công suất thành công" });
        }
 
        // ===================================================================
        // GET /api/HospitalPortal/dashboard  — Tổng hợp dữ liệu màn hình portal
        // ===================================================================
        [HttpGet("dashboard")]
        public async Task<IActionResult> GetDashboard()
        {
            var hospitalId = HttpContext.Session.GetInt32(AppConstants.SessionHospitalId); // Sử dụng hằng số
            if (hospitalId == null) return Unauthorized(new { message = "Chưa đăng nhập" });
 
            var hospital = await _context.Hospitals.FindAsync(hospitalId.Value);
            if (hospital == null) return NotFound();
 
            // Ca đang đến (PENDING chờ xác nhận)
            var pendingNotifs = await _context.HospitalNotifications
                .AsNoTracking()
                .Include(n => n.EmergencyCase).ThenInclude(e => e!.PatientProfile)
                .Where(n => n.HospitalId == hospitalId.Value && n.Status == AppConstants.CaseStatusPending)
                .OrderByDescending(n => n.CreatedAt)
                .Select(n => new
                {
                    n.Id,
                    n.EtaMinutes,
                    n.DriverName,
                    n.VehicleNo,
                    n.CreatedAt,
                    caseId = n.EmergencyCaseId,
                    emergencyType = n.EmergencyCase != null ? n.EmergencyCase.EmergencyType : "",
                    description = n.EmergencyCase != null ? n.EmergencyCase.Description : "",
                    // Username (không phải tên hiển thị) để máy chủ gửi kết quả đúng tài xế
                    driverUsername = n.EmergencyCase != null ? n.EmergencyCase.AssignedDriverUsername : null,
                    patientName = n.EmergencyCase != null && n.EmergencyCase.PatientProfile != null
                        ? n.EmergencyCase.PatientProfile.FullName : "N/A",
                    patientPhone = n.EmergencyCase != null && n.EmergencyCase.PatientProfile != null
                        ? n.EmergencyCase.PatientProfile.PhoneNumber : "N/A"
                })
                .ToListAsync();
 
            // Thống kê hôm nay
            // CreatedAt lưu theo giờ UTC nên mốc "đầu ngày hôm nay" cũng phải đổi sang UTC
            var todayStartUtc = DateTime.Today.ToUniversalTime();
            // Respond lưu trạng thái ACCEPTED (không phải "CONFIRMED") khi bệnh viện nhận ca
            var todayConfirmed = await _context.HospitalNotifications
                .AsNoTracking()
                .CountAsync(n => n.HospitalId == hospitalId.Value
                              && n.Status == AppConstants.CaseStatusAccepted
                              && n.CreatedAt >= todayStartUtc);
 
            return Ok(new
            {
                hospital = new
                {
                    hospital.Id,
                    hospital.Name,
                    hospital.AvailableEmergencyBeds,
                    hospital.TotalEmergencyBeds,
                    hospital.ReceptionStatus,
                    hospital.StatusNote,
                    hospital.StatusUpdatedAt
                },
                pendingNotifications = pendingNotifs,
                todayConfirmedCases = todayConfirmed
            });
        }
 
        public class NotificationRespondRequest
        {
            public string Status { get; set; } = "CONFIRMED"; // CONFIRMED / REJECTED
            public string? Room { get; set; }
            public string? RejectReason { get; set; }
            public string DriverUsername { get; set; } = "";
        }

        // ===================================================================
        // POST /api/HospitalPortal/notifications/{notificationId}/respond
        // ===================================================================
        [HttpPost("notifications/{notificationId}/respond")]
        public async Task<IActionResult> RespondToNotification(int notificationId, [FromBody] NotificationRespondRequest req)
        {
            if (req == null) return BadRequest(new { message = "Dữ liệu trống" });
            
            var hospitalId = HttpContext.Session.GetInt32(AppConstants.SessionHospitalId); // Sử dụng hằng số
            if (hospitalId == null) return Unauthorized(new { message = "Chưa đăng nhập" });

            var notif = await _context.HospitalNotifications
                .Include(n => n.EmergencyCase)
                .FirstOrDefaultAsync(n => n.Id == notificationId);

            if (notif == null)
                return NotFound(new { message = "Không tìm thấy notification" });

            // Chỉ bệnh viện sở hữu notification mới được respond
            if (notif.HospitalId != hospitalId.Value)
                return Forbid();

            var status = req.Status?.Trim().ToUpperInvariant();
            if (status != AppConstants.CaseStatusAccepted && status != AppConstants.CaseStatusRejected)
                return BadRequest(new { message = "Status không hợp lệ" });

            // Kiểm tra xem ca này đã được bệnh viện khác xác nhận trước đó chưa (tránh tranh chấp ca)
            if (status == AppConstants.CaseStatusAccepted)
            {
                var alreadyConfirmed = await _context.HospitalNotifications
                    .AnyAsync(n => n.EmergencyCaseId == notif.EmergencyCaseId && n.Status == AppConstants.CaseStatusAccepted && n.Id != notif.Id);
                if (alreadyConfirmed)
                {
                    return BadRequest(new { message = "Ca cấp cứu này đã được một bệnh viện khác tiếp nhận trước đó!" });
                }
            }

            notif.Status = status;
            notif.RespondedAt = DateTime.UtcNow;

            var hospital = await _context.Hospitals.FindAsync(notif.HospitalId);

            if (status == AppConstants.CaseStatusAccepted)
            {
                notif.AssignedRoom = req.Room;
                notif.RejectReason = null;

                if (notif.EmergencyCase != null)
                {
                    notif.EmergencyCase.ConfirmedHospitalId = notif.HospitalId;
                    notif.EmergencyCase.Status = AppConstants.CaseStatusDelivering;
                }

                // CẬP NHẬT DATABASE: Trừ số giường trống của bệnh viện
                if (hospital != null && hospital.AvailableEmergencyBeds > 0)
                {
                    hospital.AvailableEmergencyBeds -= 1;
                }

                // Tự động hủy (CANCELLED) yêu cầu ở tất cả các bệnh viện khác cho ca này
                var otherNotifs = await _context.HospitalNotifications
                    .Where(n => n.EmergencyCaseId == notif.EmergencyCaseId && n.Id != notif.Id && n.Status == AppConstants.CaseStatusPending)
                    .ToListAsync();
                foreach (var o in otherNotifs)
                {   // "CANCELLED" có thể là hằng số
                    o.Status = AppConstants.CaseStatusCancelled;
                }

                // Thông báo realtime cho các bệnh viện kia tải lại danh sách (để ẩn ca đã bị lấy mất)
                foreach (var o in otherNotifs)
                {
                    await _hub.Clients.Group($"Hospital_{o.HospitalId}").SendAsync(AppConstants.SignalRReceiveIncomingPatient, new
                    {
                        CaseId = notif.EmergencyCaseId,
                        IsCancelled = true
                    });
                }
            }
            else
            {
                notif.AssignedRoom = null;
                notif.RejectReason = req.RejectReason;
            }

            await _context.SaveChangesAsync();

            // Gửi realtime cho đúng driver (kèm đầy đủ tọa độ, tên bệnh viện để tự vẽ lại đường)
            // Ưu tiên tài xế đang được giao ca trên máy chủ; giá trị client gửi lên trước đây là tên hiển thị
            var driverUsername = notif.EmergencyCase?.AssignedDriverUsername ?? req.DriverUsername;
            await AmbulanceHub.SendToDriver(
                driverUsername,
                AppConstants.SignalRHospitalConfirmed,
                new
                {
                    NotificationId = notif.Id,
                    Status = notif.Status,
                    HospitalName = hospital?.Name ?? "Bệnh viện",
                    HospitalLat = hospital != null ? (double)hospital.Lat : 0.0,
                    HospitalLng = hospital != null ? (double)hospital.Lng : 0.0,
                    HospitalAddress = hospital?.Address ?? "",
                    AssignedRoom = notif.AssignedRoom,
                    RejectReason = notif.RejectReason,
                    RespondedAt = notif.RespondedAt
                },
                _hub);

            // Gửi realtime thông báo cho người nhà bệnh nhân
            if (status == AppConstants.CaseStatusAccepted)
            {
                await _hub.Clients.Group($"Case_{notif.EmergencyCaseId}").SendAsync(AppConstants.SignalRHospitalConfirmed, new
                {
                    HospitalName = hospital?.Name ?? "Bệnh viện",
                    HospitalLat = hospital != null ? (double)hospital.Lat : 0.0,
                    HospitalLng = hospital != null ? (double)hospital.Lng : 0.0,
                    AssignedRoom = notif.AssignedRoom,
                    Status = AppConstants.CaseStatusDelivering
                });
            }

            return Ok(new { success = true });
        }

        // ===================================================================
        // GET /api/HospitalPortal/logout
        // ===================================================================
        [HttpGet("logout")]
        public IActionResult Logout()
        {
            HttpContext.Session.Remove("HOSPITAL_USER_ID"); // Có thể tạo hằng số cho key này
            HttpContext.Session.Remove(AppConstants.SessionHospitalId); // Sử dụng hằng số
            HttpContext.Session.Remove(AppConstants.SessionHospitalName); // Sử dụng hằng số
            HttpContext.Session.Remove(AppConstants.SessionHospitalUsername); // Sử dụng hằng số
            return Ok(new { success = true });
        }
    }
}
