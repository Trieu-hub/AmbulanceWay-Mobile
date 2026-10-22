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
    /// API dành riêng cho app mobile của bệnh nhân (xác thực bằng JWT cấp ở /api/patientauth/verify-otp).
    /// Gửi SOS vẫn dùng POST /api/Sos như web; controller này bổ sung phần web lấy từ Session:
    /// hồ sơ, trạng thái ca hiện tại (để khôi phục khi mở lại app) và đánh giá.
    /// </summary>
    [ApiController]
    [Route("api/mobile/patient")]
    [Authorize(Roles = AppConstants.RolePatient)]
    public class MobilePatientController : ControllerBase
    {
        private readonly AmbulanceWayDbContext _context;
        private readonly IHubContext<AmbulanceHub> _hub;

        public MobilePatientController(AmbulanceWayDbContext context, IHubContext<AmbulanceHub> hub)
        {
            _context = context;
            _hub = hub;
        }

        public class UpdateProfileRequest
        {
            public string? FullName { get; set; }
            public DateTime? BirthDate { get; set; }
            public string? Gender { get; set; }
            public string? PermanentAddress { get; set; }
            public string? MedicalHistory { get; set; }
            public string? DrugAllergies { get; set; }
            public string? EmergencyContactName { get; set; }
            public string? EmergencyContactPhone { get; set; }
        }

        // PUT /api/mobile/patient/me — sửa hồ sơ y tế. Số điện thoại là định danh đăng nhập nên không đổi ở đây.
        [HttpPut("me")]
        public async Task<IActionResult> UpdateMe([FromBody] UpdateProfileRequest req)
        {
            var profileId = MobileJwt.GetPatientProfileId(User);
            if (profileId == null) return Unauthorized(new { message = "Token không hợp lệ" });

            var p = await _context.PatientProfiles.FirstOrDefaultAsync(x => x.Id == profileId.Value);
            if (p == null) return NotFound(new { message = "Không tìm thấy hồ sơ bệnh nhân" });

            static string? Clean(string? value, int max)
            {
                if (string.IsNullOrWhiteSpace(value)) return null;
                var text = value.Trim();
                return text.Length > max ? text[..max] : text;
            }

            var fullName = Clean(req.FullName, 100);
            var gender = Clean(req.Gender, 10);
            var address = Clean(req.PermanentAddress, 300);
            var contactName = Clean(req.EmergencyContactName, 100);
            var contactPhone = Clean(req.EmergencyContactPhone, 20);
            if (fullName == null || gender == null || address == null || contactName == null || contactPhone == null || req.BirthDate == null)
                return BadRequest(new { message = "Vui lòng nhập đủ họ tên, ngày sinh, giới tính, địa chỉ và người thân liên hệ" });
            if (req.BirthDate.Value.Date > DateTime.UtcNow.Date || req.BirthDate.Value.Year < 1900)
                return BadRequest(new { message = "Ngày sinh không hợp lệ" });

            p.FullName = fullName;
            p.BirthDate = req.BirthDate.Value.Date;
            p.Gender = gender;
            p.PermanentAddress = address;
            p.MedicalHistory = Clean(req.MedicalHistory, 500);
            p.DrugAllergies = Clean(req.DrugAllergies, 500);
            p.EmergencyContactName = contactName;
            p.EmergencyContactPhone = contactPhone;
            p.UpdatedAt = DateTime.UtcNow;
            await _context.SaveChangesAsync();

            return await GetMe();
        }

        public class CancelRequest
        {
            public string? Reason { get; set; }
        }

        // POST /api/mobile/patient/cases/{id}/cancel
        // Bệnh nhân hủy SOS khi xe chưa đón (đang điều phối hoặc xe đang tới). Tài xế đang được điều tới,
        // các tài xế khác (hàng chờ) và điều phối viên nhận thông báo realtime.
        [HttpPost("cases/{id:int}/cancel")]
        public async Task<IActionResult> CancelCase(int id, [FromBody] CancelRequest? req)
        {
            var profileId = MobileJwt.GetPatientProfileId(User);
            if (profileId == null) return Unauthorized(new { message = "Token không hợp lệ" });

            var ec = await _context.EmergencyCases.FirstOrDefaultAsync(e => e.Id == id && e.PatientProfileId == profileId.Value);
            if (ec == null) return NotFound(new { message = "Không tìm thấy ca cấp cứu" });

            var cancellable = new[]
            {
                AppConstants.CaseStatusPending,
                AppConstants.CaseStatusDispatching,
                AppConstants.HospitalReceptionOpen,
                AppConstants.CaseStatusAssigned,
                AppConstants.CaseStatusAccepted
            };
            if (!cancellable.Contains(ec.Status))
                return BadRequest(new { message = "Xe đã đón bệnh nhân hoặc ca đã kết thúc, không thể hủy. Hãy liên hệ tài xế hoặc gọi 115." });

            var reason = string.IsNullOrWhiteSpace(req?.Reason) ? null : req!.Reason!.Trim();
            if (reason != null && reason.Length > 200) reason = reason[..200];

            ec.Status = AppConstants.CaseStatusCancelled;
            AmbulanceHub.PendingCases.TryRemove(id, out _);
            await _context.SaveChangesAsync();

            var now = DateTime.UtcNow;
            var payload = new { CaseId = id, Reason = reason, CancelledAt = now };

            // Mọi tài xế đang trực (kể cả tài xế đã nhận ca) đều ở nhóm Drivers: người đang chờ thì bỏ ca
            // khỏi hàng chờ, người đã nhận ca thì dừng nhiệm vụ.
            await _hub.Clients.Group(AppConstants.RoleDriversGroup).SendAsync(AppConstants.SignalRCaseCancelled, payload);

            await _hub.Clients.Group(AppConstants.RoleAdminsGroup).SendAsync(AppConstants.SignalRTripStatusUpdated, new
            {
                CaseId = id,
                Status = AppConstants.CaseStatusCancelled,
                UpdatedAt = now
            });
            await _hub.Clients.Group($"Case_{id}").SendAsync(AppConstants.SignalRCaseStatusUpdated, new
            {
                CaseId = id,
                Status = AppConstants.CaseStatusCancelled,
                UpdatedAt = now
            });

            return Ok(new { success = true, message = "Đã hủy yêu cầu cấp cứu" });
        }

        // GET /api/mobile/patient/me
        [HttpGet("me")]
        public async Task<IActionResult> GetMe()
        {
            var profileId = MobileJwt.GetPatientProfileId(User);
            if (profileId == null) return Unauthorized(new { message = "Token không hợp lệ" });

            var p = await _context.PatientProfiles.AsNoTracking().FirstOrDefaultAsync(x => x.Id == profileId.Value);
            if (p == null) return NotFound(new { message = "Không tìm thấy hồ sơ bệnh nhân" });

            return Ok(new
            {
                id = p.Id,
                fullName = p.FullName,
                phoneNumber = p.PhoneNumber,
                birthDate = p.BirthDate,
                gender = p.Gender,
                permanentAddress = p.PermanentAddress,
                medicalHistory = p.MedicalHistory,
                drugAllergies = p.DrugAllergies,
                emergencyContactName = p.EmergencyContactName,
                emergencyContactPhone = p.EmergencyContactPhone,
                isOtpVerified = p.IsOtpVerified
            });
        }

        // GET /api/mobile/patient/cases/active
        // Ca đang diễn ra, hoặc ca vừa hoàn thành trong 24h mà chưa đánh giá (để app hiện lại form đánh giá)
        [HttpGet("cases/active")]
        public async Task<IActionResult> GetActiveCase()
        {
            var profileId = MobileJwt.GetPatientProfileId(User);
            if (profileId == null) return Unauthorized(new { message = "Token không hợp lệ" });

            var ec = await _context.EmergencyCases
                .AsNoTracking()
                .Include(e => e.Driver)
                .Where(e => e.PatientProfileId == profileId.Value)
                .OrderByDescending(e => e.Id)
                .FirstOrDefaultAsync();

            if (ec == null) return Ok(new { hasCase = false });

            var hasRated = await _context.PatientRatings.AnyAsync(r => r.EmergencyCaseId == ec.Id);

            var finished = ec.Status == AppConstants.CaseStatusCompleted
                        || ec.Status == AppConstants.CaseStatusCancelled
                        || ec.Status == AppConstants.CaseStatusRejected;
            var waitingForRating = ec.Status == AppConstants.CaseStatusCompleted
                                && !hasRated
                                && ec.CreatedAt > DateTime.UtcNow.AddHours(-24);

            if (finished && !waitingForRating) return Ok(new { hasCase = false });

            return Ok(new { hasCase = true, @case = await BuildSnapshotAsync(ec, hasRated) });
        }

        // GET /api/mobile/patient/cases/{id}
        [HttpGet("cases/{id:int}")]
        public async Task<IActionResult> GetCase(int id)
        {
            var profileId = MobileJwt.GetPatientProfileId(User);
            if (profileId == null) return Unauthorized(new { message = "Token không hợp lệ" });

            var ec = await _context.EmergencyCases
                .AsNoTracking()
                .Include(e => e.Driver)
                .FirstOrDefaultAsync(e => e.Id == id && e.PatientProfileId == profileId.Value);

            if (ec == null) return NotFound(new { message = "Không tìm thấy ca cấp cứu" });

            var hasRated = await _context.PatientRatings.AnyAsync(r => r.EmergencyCaseId == ec.Id);
            return Ok(await BuildSnapshotAsync(ec, hasRated));
        }

        public class RatingRequest
        {
            public int OverallRating { get; set; }
            public int ResponseTimeRating { get; set; }
            public int DriverAttitudeRating { get; set; }
            public int VehicleConditionRating { get; set; }
            public int SituationHandlingRating { get; set; }
            public string? Comment { get; set; }
        }

        // POST /api/mobile/patient/cases/{id}/rating
        [HttpPost("cases/{id:int}/rating")]
        public async Task<IActionResult> SubmitRating(int id, [FromBody] RatingRequest req)
        {
            var profileId = MobileJwt.GetPatientProfileId(User);
            if (profileId == null) return Unauthorized(new { message = "Token không hợp lệ" });

            var ec = await _context.EmergencyCases
                .FirstOrDefaultAsync(e => e.Id == id && e.PatientProfileId == profileId.Value);
            if (ec == null)
                return NotFound(new { message = "Không tìm thấy ca hoặc bạn không có quyền đánh giá" });

            if (ec.Status != AppConstants.CaseStatusCompleted)
                return BadRequest(new { message = "Ca chưa hoàn thành, chưa thể đánh giá" });

            if (await _context.PatientRatings.AnyAsync(r => r.EmergencyCaseId == id))
                return BadRequest(new { message = "Ca này đã được đánh giá rồi" });

            var scores = new[] { req.OverallRating, req.ResponseTimeRating, req.DriverAttitudeRating,
                                 req.VehicleConditionRating, req.SituationHandlingRating };
            if (scores.Any(s => s < 1 || s > 5))
                return BadRequest(new { message = "Điểm đánh giá phải từ 1 đến 5" });

            var comment = req.Comment?.Trim();
            if (comment != null && comment.Length > 1000) comment = comment.Substring(0, 1000);

            var rating = new PatientRating
            {
                EmergencyCaseId = id,
                PatientProfileId = profileId.Value,
                OverallRating = req.OverallRating,
                ResponseTimeRating = req.ResponseTimeRating,
                DriverAttitudeRating = req.DriverAttitudeRating,
                VehicleConditionRating = req.VehicleConditionRating,
                SituationHandlingRating = req.SituationHandlingRating,
                Comment = string.IsNullOrEmpty(comment) ? null : comment,
                CreatedAt = DateTime.UtcNow
            };
            _context.PatientRatings.Add(rating);
            await _context.SaveChangesAsync();

            return Ok(new { success = true, ratingId = rating.Id, message = "Cảm ơn bạn đã đánh giá!" });
        }

        // Ảnh chụp trạng thái ca: app gọi khi mở màn hình theo dõi và sau mỗi lần SignalR kết nối lại
        private async Task<object> BuildSnapshotAsync(EmergencyCase ec, bool hasRated)
        {
            object? hospital = null;
            if (ec.ConfirmedHospitalId.HasValue)
            {
                var h = await _context.Hospitals.AsNoTracking().FirstOrDefaultAsync(x => x.Id == ec.ConfirmedHospitalId.Value);
                if (h != null)
                {
                    var room = await _context.HospitalNotifications
                        .AsNoTracking()
                        .Where(n => n.EmergencyCaseId == ec.Id && n.HospitalId == h.Id && n.AssignedRoom != null)
                        .OrderByDescending(n => n.Id)
                        .Select(n => n.AssignedRoom)
                        .FirstOrDefaultAsync();

                    hospital = new
                    {
                        id = h.Id,
                        name = h.Name,
                        address = h.Address,
                        lat = (double)h.Lat,
                        lng = (double)h.Lng,
                        assignedRoom = room
                    };
                }
            }

            object? driver = null;
            object? driverLocation = null;
            if (!string.IsNullOrEmpty(ec.AssignedDriverUsername))
            {
                driver = new
                {
                    username = ec.AssignedDriverUsername,
                    name = ec.AssignedDriverName,
                    vehicle = ec.AssignedVehicleNo,
                    phone = ec.Driver?.Phone
                };

                if (AmbulanceHub.TryGetDriverLocation(ec.AssignedDriverUsername, out var loc))
                {
                    driverLocation = new
                    {
                        lat = loc.Lat,
                        lng = loc.Lng,
                        updatedAt = DateTime.SpecifyKind(loc.UpdatedAtUtc, DateTimeKind.Utc)
                    };
                }
            }

            return new
            {
                id = ec.Id,
                status = ec.Status,
                emergencyType = ec.EmergencyType,
                description = ec.Description,
                patientAddress = ec.PatientAddress,
                patientLat = (double)ec.PatientLat,
                patientLng = (double)ec.PatientLng,
                createdAt = DateTime.SpecifyKind(ec.CreatedAt, DateTimeKind.Utc),
                acceptedAt = ec.AcceptedAt.HasValue ? DateTime.SpecifyKind(ec.AcceptedAt.Value, DateTimeKind.Utc) : (DateTime?)null,
                driver,
                driverLocation,
                hospital,
                hasRated
            };
        }
    }
}
