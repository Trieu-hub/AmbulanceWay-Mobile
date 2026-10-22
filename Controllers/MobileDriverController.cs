using AmbulanceWay.Constants;
using AmbulanceWay.Data;
using AmbulanceWay.Hubs;
using AmbulanceWay.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;

namespace AmbulanceWay.Controllers.Api
{
    /// <summary>
    /// API dành riêng cho app mobile của tài xế (xác thực bằng JWT cấp ở /api/auth/login).
    /// Nhận ca và cập nhật trạng thái vẫn dùng /api/Sos như web; controller này bổ sung phần
    /// web lấy từ Session: thông tin tài xế, ca đang chờ/đang làm, bệnh viện đích và lịch sử chuyến.
    /// </summary>
    [ApiController]
    [Route("api/mobile/driver")]
    [Authorize(Roles = AppConstants.RoleDriver)]
    public class MobileDriverController : ControllerBase
    {
        private readonly AmbulanceWayDbContext _context;
        private readonly IHubContext<AmbulanceHub> _hub;

        private const string DefaultStation = "Bệnh viện Columbia Asia";

        public MobileDriverController(AmbulanceWayDbContext context, IHubContext<AmbulanceHub> hub)
        {
            _context = context;
            _hub = hub;
        }

        private string CurrentUsername => User.Identity?.Name ?? "";

        // Token còn hạn 7 ngày nên phải kiểm tra lại tài khoản còn tồn tại / chưa bị khóa ở mỗi request
        private async Task<(Driver? driver, IActionResult? error)> LoadDriverAsync(bool createIfMissing = false)
        {
            var username = CurrentUsername;
            var user = await _context.Users.FirstOrDefaultAsync(u => u.Username == username);
            if (user == null)
                return (null, Unauthorized(new { message = "Tài khoản không còn tồn tại" }));
            if (user.Status != AppConstants.StatusActive)
                return (null, StatusCode(StatusCodes.Status403Forbidden, new { message = "Tài khoản đang bị khóa!" }));

            var driver = await _context.Drivers.FirstOrDefaultAsync(d => d.UserId == user.Id);
            if (driver == null && createIfMissing)
            {
                // Giống AccountController.Login: user DRIVER chưa có hồ sơ tài xế thì tạo mặc định
                driver = new Driver
                {
                    UserId = user.Id,
                    DriverName = user.Username,
                    Vehicle = "N/A",
                    Phone = "N/A",
                    LicenseNo = "N/A",
                    Station = DefaultStation,
                    Status = AppConstants.StatusOffline
                };
                _context.Drivers.Add(driver);
                await _context.SaveChangesAsync();
            }

            if (driver == null)
                return (null, NotFound(new { message = "Không tìm thấy hồ sơ tài xế" }));

            return (driver, null);
        }

        // GET /api/mobile/driver/me
        [HttpGet("me")]
        public async Task<IActionResult> GetMe()
        {
            var (driver, error) = await LoadDriverAsync(createIfMissing: true);
            if (error != null) return error;

            var station = string.IsNullOrEmpty(driver!.Station) ? DefaultStation : driver.Station;
            var coords = AccountController.StationCoords.TryGetValue(station, out var c)
                ? c
                : AccountController.StationCoords[DefaultStation];

            return Ok(new
            {
                username = CurrentUsername,
                driverId = driver.Id,
                driverName = driver.DriverName,
                vehicle = driver.Vehicle,
                phone = driver.Phone,
                licenseNo = driver.LicenseNo,
                station,
                stationLat = coords.lat,
                stationLng = coords.lng,
                status = driver.Status
            });
        }

        public class DriverStatusRequest
        {
            public string Status { get; set; } = "";
        }

        // POST /api/mobile/driver/status  — ONLINE khi bắt đầu ca trực, OFFLINE khi kết thúc
        [HttpPost("status")]
        public async Task<IActionResult> UpdateStatus([FromBody] DriverStatusRequest req)
        {
            var (driver, error) = await LoadDriverAsync();
            if (error != null) return error;

            var status = req.Status?.Trim().ToUpperInvariant();
            if (status != AppConstants.StatusOnline && status != AppConstants.StatusOffline)
                return BadRequest(new { message = "Trạng thái không hợp lệ" });

            driver!.Status = status;
            await _context.SaveChangesAsync();
            return Ok(new { success = true, status = driver.Status });
        }

        // GET /api/mobile/driver/cases/pending
        // Ca chưa ai nhận trong 2 giờ gần đây + ca Admin đã chỉ định cho tài xế này.
        // Web chỉ biết các ca này qua SignalR; app cần đọc lại vì có thể mở sau khi SOS đã phát.
        [HttpGet("cases/pending")]
        public async Task<IActionResult> GetPendingCases()
        {
            var (_, error) = await LoadDriverAsync();
            if (error != null) return error;

            var username = CurrentUsername;
            var since = DateTime.UtcNow.AddHours(-2);
            var waiting = new[]
            {
                AppConstants.CaseStatusPending,
                AppConstants.CaseStatusDispatching,
                AppConstants.HospitalReceptionOpen
            };

            var rows = await _context.EmergencyCases
                .AsNoTracking()
                .Where(e => (waiting.Contains(e.Status) && e.AssignedDriverUsername == null && e.CreatedAt >= since)
                         || (e.Status == AppConstants.CaseStatusAssigned && e.AssignedDriverUsername == username))
                .OrderByDescending(e => e.Id)
                .Take(20)
                .ToListAsync();

            return Ok(rows.Select(e => new
            {
                caseId = e.Id,
                status = e.Status,
                emergencyType = e.EmergencyType,
                description = e.Description,
                address = e.PatientAddress,
                lat = (double)e.PatientLat,
                lng = (double)e.PatientLng,
                createdAt = DateTime.SpecifyKind(e.CreatedAt, DateTimeKind.Utc)
            }));
        }

        // GET /api/mobile/driver/cases/active  — Ca tài xế đang thực hiện (khôi phục khi mở lại app)
        [HttpGet("cases/active")]
        public async Task<IActionResult> GetActiveCase()
        {
            var (_, error) = await LoadDriverAsync();
            if (error != null) return error;

            var username = CurrentUsername;
            var active = new[]
            {
                AppConstants.CaseStatusAccepted,
                AppConstants.CaseStatusPickedUp,
                AppConstants.CaseStatusDelivering
            };

            var ec = await _context.EmergencyCases
                .AsNoTracking()
                .Include(e => e.PatientProfile)
                .Where(e => e.AssignedDriverUsername == username && active.Contains(e.Status))
                .OrderByDescending(e => e.Id)
                .FirstOrDefaultAsync();

            if (ec == null) return Ok(new { hasCase = false });

            object? hospital = null;
            if (ec.ConfirmedHospitalId.HasValue)
            {
                var h = await _context.Hospitals.AsNoTracking().FirstOrDefaultAsync(x => x.Id == ec.ConfirmedHospitalId.Value);
                if (h != null) hospital = ToHospitalDto(h);
            }

            var p = ec.PatientProfile;
            return Ok(new
            {
                hasCase = true,
                @case = new
                {
                    caseId = ec.Id,
                    status = ec.Status,
                    emergencyType = ec.EmergencyType,
                    description = ec.Description,
                    address = ec.PatientAddress,
                    lat = (double)ec.PatientLat,
                    lng = (double)ec.PatientLng,
                    createdAt = DateTime.SpecifyKind(ec.CreatedAt, DateTimeKind.Utc),
                    acceptedAt = ec.AcceptedAt.HasValue ? DateTime.SpecifyKind(ec.AcceptedAt.Value, DateTimeKind.Utc) : (DateTime?)null,
                    // Thông tin y tế chỉ trả cho tài xế đã nhận ca
                    patient = p == null ? null : new
                    {
                        fullName = p.FullName,
                        phoneNumber = p.PhoneNumber,
                        gender = p.Gender,
                        birthDate = p.BirthDate,
                        medicalHistory = p.MedicalHistory,
                        drugAllergies = p.DrugAllergies,
                        emergencyContactName = p.EmergencyContactName,
                        emergencyContactPhone = p.EmergencyContactPhone
                    },
                    hospital
                }
            });
        }

        public class DestinationRequest
        {
            public int HospitalId { get; set; }
        }

        // POST /api/mobile/driver/cases/{id}/destination
        // Tài xế tự chọn bệnh viện đích sau khi đón bệnh nhân (không phải chờ bệnh viện bấm xác nhận).
        // Ghi ConfirmedHospitalId để lịch sử chuyến có tên bệnh viện, và báo cho người nhà qua SignalR.
        [HttpPost("cases/{id:int}/destination")]
        public async Task<IActionResult> SetDestination(int id, [FromBody] DestinationRequest req)
        {
            var (_, error) = await LoadDriverAsync();
            if (error != null) return error;

            var ec = await _context.EmergencyCases.FirstOrDefaultAsync(e => e.Id == id);
            if (ec == null) return NotFound(new { message = "Không tìm thấy ca cấp cứu" });

            if (!string.Equals(ec.AssignedDriverUsername, CurrentUsername, StringComparison.OrdinalIgnoreCase))
                return StatusCode(StatusCodes.Status403Forbidden, new { message = "Ca này không phải do bạn thực hiện" });

            if (ec.Status != AppConstants.CaseStatusPickedUp && ec.Status != AppConstants.CaseStatusDelivering)
                return BadRequest(new { message = "Chỉ chọn bệnh viện sau khi đã đón bệnh nhân" });

            var hospital = await _context.Hospitals.AsNoTracking().FirstOrDefaultAsync(h => h.Id == req.HospitalId && h.IsActive);
            if (hospital == null) return NotFound(new { message = "Không tìm thấy bệnh viện" });

            ec.ConfirmedHospitalId = hospital.Id;
            ec.Status = AppConstants.CaseStatusDelivering;
            await _context.SaveChangesAsync();

            var now = DateTime.UtcNow;

            // Cùng event với lúc bệnh viện xác nhận (HospitalPortalController) để trang theo dõi của người nhà dùng lại được
            await _hub.Clients.Group($"Case_{id}").SendAsync(AppConstants.SignalRHospitalConfirmed, new
            {
                HospitalName = hospital.Name,
                HospitalLat = (double)hospital.Lat,
                HospitalLng = (double)hospital.Lng,
                AssignedRoom = (string?)null,
                Status = AppConstants.CaseStatusDelivering
            });

            await _hub.Clients.Group($"Case_{id}").SendAsync(AppConstants.SignalRCaseStatusUpdated, new
            {
                CaseId = id,
                Status = AppConstants.CaseStatusDelivering,
                UpdatedAt = now
            });

            await _hub.Clients.Group(AppConstants.RoleAdminsGroup).SendAsync(AppConstants.SignalRTripStatusUpdated, new
            {
                CaseId = id,
                Status = AppConstants.CaseStatusDelivering,
                UpdatedAt = now
            });

            return Ok(new { success = true, hospital = ToHospitalDto(hospital) });
        }

        // GET /api/mobile/driver/trips?page=1&pageSize=20  — Lịch sử chuyến của riêng tài xế này
        [HttpGet("trips")]
        public async Task<IActionResult> GetTrips([FromQuery] int page = 1, [FromQuery] int pageSize = 20)
        {
            var (driver, error) = await LoadDriverAsync();
            if (error != null) return error;

            page = Math.Max(page, 1);
            pageSize = Math.Clamp(pageSize, 1, 100);

            var query = _context.TripHistories.AsNoTracking().Where(t => t.DriverName == driver!.DriverName);

            var total = await query.CountAsync();
            var totalDistanceKm = total == 0 ? 0 : await query.SumAsync(t => t.DistanceKm);

            var rows = await query
                .OrderByDescending(t => t.CreatedAt)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .ToListAsync();

            return Ok(new
            {
                total,
                totalDistanceKm = Math.Round(totalDistanceKm, 2),
                page,
                pageSize,
                data = rows.Select(t => new
                {
                    id = t.Id,
                    hospitalName = t.HospitalName,
                    patientAddress = t.PatientAddress,
                    distanceKm = t.DistanceKm,
                    durationMinutes = t.DurationMinutes,
                    tripStatus = t.TripStatus,
                    createdAt = DateTime.SpecifyKind(t.CreatedAt, DateTimeKind.Utc),
                    completedAt = t.CompletedAt.HasValue ? DateTime.SpecifyKind(t.CompletedAt.Value, DateTimeKind.Utc) : (DateTime?)null
                })
            });
        }

        private static object ToHospitalDto(Hospital h) => new
        {
            id = h.Id,
            name = h.Name,
            address = h.Address,
            lat = (double)h.Lat,
            lng = (double)h.Lng,
            phone = h.Phone
        };
    }
}
