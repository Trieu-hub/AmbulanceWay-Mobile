using AmbulanceWay.Data;
using AmbulanceWay.Hubs;
using AmbulanceWay.Models;
using Microsoft.AspNetCore.SignalR;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using AmbulanceWay.Constants;
using Microsoft.EntityFrameworkCore;
using System.Linq;

namespace AmbulanceWay.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class SosController : ControllerBase
    {
        private readonly AmbulanceWayDbContext _context;
        private readonly IHubContext<AmbulanceHub> _hub;
        private readonly ILogger<SosController> _logger;

        private const double RadiusKm = 5;

        public SosController(AmbulanceWayDbContext context, IHubContext<AmbulanceHub> hub, ILogger<SosController> logger)
        {
            _context = context;
            _hub = hub;
            _logger = logger;
        }

        public class SosRequest
        {
            public string EmergencyType { get; set; } = null!;
            public string Description { get; set; } = null!;
            public int PatientProfileId { get; set; }
            public double PatientLat { get; set; }
            public double PatientLng { get; set; }
            public string PatientAddress { get; set; } = null!;
        }

        public class AcceptCaseRequest
        {
            public string DriverUsername { get; set; } = null!;
        }

        public class AssignCaseRequest
        {
            public string DriverUsername { get; set; } = null!;
        }

        public class StatusUpdateRequest
        {
            public string Status { get; set; } = null!; 
            public string? Note { get; set; }
            public double? DistanceKm { get; set; }
            public int? DurationMinutes { get; set; }
            public List<int>? TargetHospitalIds { get; set; } // Dùng cho Phase 2: Phát tín hiệu đến 1-3 BV
        }

        [HttpPost]
        public async Task<IActionResult> Create([FromBody] SosRequest req)
        {
            if (req == null) return BadRequest(new { message = "Dữ liệu yêu cầu không hợp lệ." });

            // Bắt đầu theo dõi Escalation (Phần 3)
            // AmbulanceHub.PendingCases[ec.Id] = DateTime.UtcNow; (Sẽ thêm sau khi save)

            var profile = await _context.PatientProfiles.FirstOrDefaultAsync(p => p.Id == req.PatientProfileId);
            if (profile == null) return BadRequest(new { message = "Không tìm thấy profile bệnh nhân" });
            if (!profile.IsOtpVerified) return BadRequest(new { message = "Profile chưa được xác thực OTP" });

            // lưu case
            var ec = new EmergencyCase
            {
                EmergencyType = req.EmergencyType,
                Description = req.Description,
                PatientProfileId = req.PatientProfileId,
                PatientLat = (decimal)req.PatientLat,
                PatientLng = (decimal)req.PatientLng,
                PatientAddress = req.PatientAddress,
                Status = AppConstants.CaseStatusPending,
                CreatedAt = DateTime.UtcNow
            };
            _context.EmergencyCases.Add(ec);
            await _context.SaveChangesAsync();

            AmbulanceHub.PendingCases[ec.Id] = DateTime.UtcNow;

            // LUÔN thông báo cho Admin ngay khi có ca mới
            await _hub.Clients.Group(AppConstants.RoleAdminsGroup).SendAsync(AppConstants.SignalRReceiveEmergencyCall, new
            {
                CaseId = ec.Id,
                Loc = req.PatientAddress,
                Lat = req.PatientLat,
                Lng = req.PatientLng,
                Patient = req.EmergencyType + ": " + req.Description,
                PatientProfileId = req.PatientProfileId
            });

            // Query driver online + filter theo bán kính 5km (V1: dùng cache realtime của driver)
            // Cách làm: lấy toàn bộ driver ONLINE, rồi nếu có location cache và khoảng cách <= 5km => dispatch.
            var drivers = await _context.Drivers
                .Include(d => d.User)
                .AsNoTracking()
                .Where(d => d.Status == AppConstants.StatusOnline)
                .ToListAsync();

            var targetLat = (double)req.PatientLat;
            var targetLng = (double)req.PatientLng;

            int matched = 0;

            foreach (var d in drivers)
            {
                var driverUsername = d.User?.Username;
                if (string.IsNullOrWhiteSpace(driverUsername))
                    continue;

                if (!AmbulanceHub.TryGetDriverLocation(driverUsername, out var loc) )
                    continue;

                // hết hạn cache (5 phút)
                if ((DateTime.UtcNow - loc.UpdatedAtUtc).TotalMinutes > 5)
                    continue;

                var dist = DistanceKm(loc.Lat, loc.Lng, targetLat, targetLng);
                    if (dist <= RadiusKm)
                    {
                        matched++;

                        // Ước lượng ETA dựa trên khoảng cách tới vị trí GPS realtime của tài xế
                        // (giả định tốc độ trung bình 25km/h để UI có số phút hợp lý)
                        const double avgSpeedKmPerHour = 25;
                        var etaMinutes = (int)Math.Ceiling((dist / avgSpeedKmPerHour) * 60);

                        // Gửi riêng lệnh realtime tới tất cả tài xế nằm trong bán kính 5km
                        var connectionId = AmbulanceHub.GetConnectionByUsername(d.User?.Username ?? string.Empty);
                        if (!string.IsNullOrEmpty(connectionId)) {
                            await _hub.Clients.Client(connectionId)
                            .SendAsync(AppConstants.SignalRReceiveNewTrip, new {
                                TripId = 0,
                                StaffName = d.DriverName,
                                Address = req.PatientAddress,
                                Hospital = req.EmergencyType + ": " + req.Description,
                                Lat = req.PatientLat,
                                Lng = req.PatientLng,
                                CaseId = ec.Id,
                                Driver = d.DriverName,
                                EtaMinutes = etaMinutes
                            });
                        }
                    }
            }

            // V1 fallback: nếu không match ai, vẫn dispatch để bạn test UI
            if (matched == 0)
            {
                // Dispatch cho toàn bộ Driver đang Online nếu không tìm thấy vị trí GPS trong cache
                await _hub.Clients.Group(AppConstants.RoleDriversGroup).SendAsync(AppConstants.SignalRReceiveNewTrip, new
                {
                    TripId = 0,
                    StaffName = "Hệ thống",
                    Address = req.PatientAddress,
                    Hospital = req.EmergencyType + ": " + req.Description,
                    Lat = req.PatientLat,
                    Lng = req.PatientLng,
                    CaseId = ec.Id,
                    Driver = "N/A",
                    EtaMinutes = 15 // Mặc định cho trường hợp fallback
                });
            }

            return Ok(new { success = true, caseId = ec.Id });
        }

        // ===================================================================
        // POST /api/Sos/{id}/accept
        // Tài xế xác nhận nhận ca cấp cứu
        // ===================================================================
        [HttpPost("{id}/accept")]
        public async Task<IActionResult> Accept(int id, [FromBody] AcceptCaseRequest req)
        {
            var driver = await _context.Drivers
                .Include(d => d.User)
                .OrderBy(d => d.Id)
                .FirstOrDefaultAsync(d => d.User.Username.ToLower() == req.DriverUsername.ToLower());

            if (driver == null) return BadRequest(new { message = "Tài xế không tồn tại" });

            // Mỗi tài xế chỉ làm một ca một lúc (web và app chỉ hiển thị được một nhiệm vụ đang chạy)
            var busyStatuses = new[] { AppConstants.CaseStatusAccepted, AppConstants.CaseStatusPickedUp, AppConstants.CaseStatusDelivering };
            var busyCaseId = await _context.EmergencyCases
                .AsNoTracking()
                .Where(e => e.Id != id && e.AssignedDriverUsername == driver.User.Username && busyStatuses.Contains(e.Status))
                .Select(e => (int?)e.Id)
                .FirstOrDefaultAsync();
            if (busyCaseId != null)
                return BadRequest(new { message = $"Bạn đang thực hiện ca #{busyCaseId}. Hãy hoàn thành ca đó trước khi nhận ca mới." });

            // Bug #4 fix: Dùng transaction để tránh race condition — chỉ 1 tài xế được Accept
            var strategy = _context.Database.CreateExecutionStrategy();
            return await strategy.ExecuteAsync<IActionResult>(async () =>
            {
                await using var transaction = await _context.Database.BeginTransactionAsync();
                try
                {
                    // Dùng ExecuteSqlRaw để lock row khi đọc (tránh 2 tài xế cùng thấy OPEN)
                    var ec = await _context.EmergencyCases
                        .FromSqlRaw("SELECT * FROM EmergencyCases WITH (UPDLOCK, ROWLOCK) WHERE Id = {0}", id)
                        .FirstOrDefaultAsync();

                    if (ec == null) return NotFound(new { message = "Không tìm thấy ca cấp cứu" });

                    // Kiểm tra nếu ca đã được chỉ định cho tài xế khác (Manual Dispatch)
                    if (ec.Status == AppConstants.CaseStatusAssigned && 
                        !string.Equals(ec.AssignedDriverUsername, req.DriverUsername, StringComparison.OrdinalIgnoreCase))
                    {
                        return BadRequest(new { message = "Ca này đã được Admin chỉ định cho một tài xế khác." });
                    }

                    // IDEMPOTENCY: Nếu tài xế này đã nhận ca rồi, trả về thành công luôn để UI vẽ lộ trình
                    if (string.Equals(ec.Status, AppConstants.CaseStatusAccepted, StringComparison.OrdinalIgnoreCase) && 
                        string.Equals(ec.AssignedDriverUsername, req.DriverUsername, StringComparison.OrdinalIgnoreCase))
                    {
                        await transaction.RollbackAsync();
                        return Ok(new { success = true, message = "Bạn đang thực hiện ca này." });
                    }

                    // CHỈ cho phép nhận ca khi ở các trạng thái chờ (PENDING, DISPATCHING, OPEN, ASSIGNED)
                    var validStatuses = new List<string> { 
                        AppConstants.CaseStatusPending,
                        AppConstants.CaseStatusDispatching,
                        AppConstants.HospitalReceptionOpen,
                        AppConstants.CaseStatusAssigned
                    };

                    // SỬA LỖI CS0019: So sánh chính xác trạng thái
                    if (ec.Status == null || !validStatuses.Contains(ec.Status))
                    {
                        // Debug rõ trạng thái hiện tại để biết vì sao reject
                        _logger.LogWarning(
                            "Accept reject CaseId={CaseId} by Driver={DriverUsername}. CurrentStatus={Status}, AssignedDriverUsername={AssignedDriverUsername}",
                            ec.Id,
                            req.DriverUsername,
                            ec.Status,
                            ec.AssignedDriverUsername);

                        return BadRequest(new { message = "Ca này đã được tiếp nhận hoặc đã kết thúc." });
                    }

                    // Cập nhật trạng thái Database
                    ec.Status = AppConstants.CaseStatusAccepted;
                    ec.DriverId = driver.Id;
                    ec.AssignedDriverUsername = driver.User?.Username;
                    ec.AssignedDriverName = driver.DriverName;
                    ec.AssignedVehicleNo = driver.Vehicle;
                    ec.AcceptedAt = DateTime.UtcNow;

                    // Loại bỏ khỏi danh sách Escalation ngay khi có người nhận
                    AmbulanceHub.PendingCases.TryRemove(id, out _);

                    await _context.SaveChangesAsync();
                    await transaction.CommitAsync();
                }
                catch
                {
                    await transaction.RollbackAsync();
                    return StatusCode(500, new { message = "Lỗi hệ thống khi tiếp nhận ca, vui lòng thử lại" });
                }

            // Thông báo Real-time cho Admin và các tài xế khác
            await _hub.Clients.Group(AppConstants.RoleAdminsGroup).SendAsync(AppConstants.SignalRNotifyCaseAccepted, new
            {
                CaseId = id,
                Driver = driver.DriverName,
                Vehicle = driver.Vehicle,
                AcceptedAt = DateTime.UtcNow
            });

            await _hub.Clients.Group(AppConstants.RoleDriversGroup).SendAsync(AppConstants.SignalRCaseAlreadyTaken, new
            {
                CaseId = id,
                TakenBy = driver.DriverName
            });

            // Thông báo Real-time cho người nhà bệnh nhân
            await _hub.Clients.Group($"Case_{id}").SendAsync("CaseAccepted", new
            {
                CaseId = id,
                DriverName = driver.DriverName,
                Vehicle = driver.Vehicle,
                Phone = driver.Phone,
                AcceptedAt = DateTime.UtcNow
            });

            return Ok(new { success = true, message = "Đã tiếp nhận ca thành công" });
            });
        }

        // ===================================================================
        // POST /api/Sos/{id}/assign
        // Admin chỉ định tài xế cụ thể cho ca cấp cứu (Manual Dispatch)
        // ===================================================================
        [HttpPost("{id}/assign-driver")]
        public async Task<IActionResult> Assign(int id, [FromBody] AssignCaseRequest req)
        {
            // Kiểm tra quyền Admin từ Session
            var role = HttpContext.Session.GetInt32(AppConstants.SessionRole);
            if (role != AppConstants.RoleValueAdmin) return Forbid();

            var driver = await _context.Drivers
                .Include(d => d.User)
                .FirstOrDefaultAsync(d => d.User.Username == req.DriverUsername);

            if (driver == null) return BadRequest(new { message = "Tài xế không tồn tại" });
            if (driver.Status != AppConstants.StatusOnline) 
                return BadRequest(new { message = "Tài xế hiện không trực tuyến hoặc đang bận" });

            var ec = await _context.EmergencyCases.FindAsync(id);
            if (ec == null) return NotFound(new { message = "Không tìm thấy ca cấp cứu" });
            
            // SỬA LỖI: Cho phép Admin điều phối nếu ca chưa có người thực hiện (Chờ, Leo thang hoặc Seeded)
            if (ec.Status != AppConstants.CaseStatusPending && 
                ec.Status != AppConstants.CaseStatusDispatching &&
                ec.Status != AppConstants.HospitalReceptionOpen &&
                ec.Status != AppConstants.CaseStatusAssigned)
                return BadRequest(new { message = $"Ca này đang ở trạng thái {ec.Status}, không thể gán lại." });

            // Cập nhật trạng thái
            // Chuyển sang ASSIGNED (Đã gán) để tài xế có thể thực hiện hành động ACCEPT (Xác nhận)
            ec.Status = AppConstants.CaseStatusAssigned;
            ec.DriverId = driver.Id;
            ec.AssignedDriverUsername = driver.User?.Username;
            ec.AssignedDriverName = driver.DriverName;
            ec.AssignedVehicleNo = driver.Vehicle;
            ec.AcceptedAt = DateTime.UtcNow;

            AmbulanceHub.PendingCases.TryRemove(id, out _);
            await _context.SaveChangesAsync();

            // 1. Thông báo cho Tài xế (Dùng event ReceiveNewTrip để kích hoạt UI nhận ca)
            var driverConnId = AmbulanceHub.GetConnectionByUsername(req.DriverUsername);
            if (!string.IsNullOrEmpty(driverConnId))
            {
                await _hub.Clients.Client(driverConnId).SendAsync(AppConstants.SignalRReceiveNewTrip, new {
                    TripId = 0,
                    Address = ec.PatientAddress,
                    Hospital = ec.EmergencyType + ": " + ec.Description,
                    Lat = (double)ec.PatientLat,
                    Lng = (double)ec.PatientLng,
                    CaseId = ec.Id,
                    EtaMinutes = 5 // Ước tính nhanh cho Admin Assign
                });
            }

            // 2. Thông báo cho Người nhà
            await _hub.Clients.Group($"Case_{id}").SendAsync("CaseAccepted", new {
                CaseId = id,
                DriverName = driver.DriverName,
                Vehicle = driver.Vehicle,
                Phone = driver.Phone
            });

            // 3. Thông báo cho các Admin khác
            await _hub.Clients.Group(AppConstants.RoleAdminsGroup).SendAsync(AppConstants.SignalRNotifyCaseAccepted, new {
                CaseId = id,
                Driver = driver.DriverName,
                IsManual = true
            });

            return Ok(new { success = true, message = "Đã gán xe thành công" });
        }

        // ===================================================================
        // GET /api/Sos/{id}/nearby-drivers
        // Lấy danh sách tài xế online sắp xếp theo khoảng cách tới ca SOS
        // ===================================================================
        [HttpGet("{id}/nearby-drivers")]
        public async Task<IActionResult> GetNearbyDrivers(int id)
        {
            var ec = await _context.EmergencyCases.FindAsync(id);
            if (ec == null) return NotFound();

            var onlineDrivers = await _context.Drivers
                .Include(d => d.User)
                .OrderBy(d => d.Id)
                .Where(d => d.Status == AppConstants.StatusOnline)
                .ToListAsync();

            var driverLocations = AmbulanceHub.GetDriverLocations();
            
            var result = onlineDrivers
                .Select(d => {
                    double dist = -1;
                    if (d.User != null && driverLocations.TryGetValue(d.User.Username, out var loc))
                    {
                        dist = DistanceKm(loc.Lat, loc.Lng, (double)ec.PatientLat, (double)ec.PatientLng);
                    }
                    return new {
                        username = d.User?.Username,
                        name = d.DriverName,
                        vehicle = d.Vehicle,
                        distance = dist,
                        distanceStr = dist >= 0 ? $"{dist:F2} km" : "Không rõ vị trí"
                    };
                })
                .OrderBy(d => d.distance == -1) // Đưa những người không rõ vị trí xuống cuối
                .ThenBy(d => d.distance)
                .ToList();

            return Ok(result);
        }

        // ===================================================================
        // PUT /api/Sos/{id}/status
        // Cập nhật tiến trình của ca (Đã đến, Đã đón bệnh, Đang về viện...)
        // ===================================================================
        [HttpPut("{id}/status")]
        public async Task<IActionResult> UpdateStatus(int id, [FromBody] StatusUpdateRequest req)
        {
            var ec = await _context.EmergencyCases
                .Include(e => e.Driver)
                    .ThenInclude(d => d!.User)
                .Include(e => e.PatientProfile)
                .OrderByDescending(e => e.Id)
                .FirstOrDefaultAsync(e => e.Id == id);

            if (ec == null) return NotFound(new { message = $"Lỗi: Ca cấp cứu ID #{id} không tồn tại trên hệ thống." });

            // Bảo vệ: Không cho phép cập nhật nếu ca đã hoàn thành hoặc bị hủy
            if (ec.Status == AppConstants.CaseStatusCompleted || ec.Status == AppConstants.CaseStatusCancelled)
            {
                return BadRequest(new { message = "Ca cấp cứu này đã kết thúc, không thể cập nhật trạng thái mới." });
            }

            ec.Status = req.Status;
            
            // Logic Chuyên nghiệp: Tách biệt các hành động theo trạng thái
            switch (req.Status)
            {
                case AppConstants.CaseStatusPickedUp:
                    // Khi đã đón bệnh nhân
                    await HandlePickedUp(ec);
                    break;
                case AppConstants.CaseStatusCompleted:
                    // Khi hoàn thành
                    await FinalizeTrip(ec, req.DistanceKm, req.DurationMinutes);
                    break;
            }

            await _context.SaveChangesAsync();

            // Broadcast cho Admin
            await _hub.Clients.Group(AppConstants.RoleAdminsGroup).SendAsync(AppConstants.SignalRTripStatusUpdated, new
            {
                CaseId = id,
                Status = req.Status,
                UpdatedAt = DateTime.UtcNow
            });

            // Broadcast cho Người nhà Bệnh nhân
            await _hub.Clients.Group($"Case_{id}").SendAsync("CaseStatusUpdated", new
            {
                CaseId = id,
                Status = req.Status,
                UpdatedAt = DateTime.UtcNow
            });

            return Ok(new { success = true });
        }

        private async Task HandlePickedUp(EmergencyCase ec)
        {
            // YÊU CẦU: Quét và gửi SOS đến các bệnh viện trong bán kính 5km nội đô
            var nearbyHospitals = await GetHospitalsInRadius(ec.PatientLat, ec.PatientLng, 5.0);
            var incoming = new List<(int HospitalId, int EtaMinutes)>();
            
            foreach (var h in nearbyHospitals)
            {
                double dist = DistanceKm((double)ec.PatientLat, (double)ec.PatientLng, (double)h.Lat, (double)h.Lng);
                int etaMinutes = (int)Math.Ceiling((dist / 25.0) * 60);
                if (etaMinutes < 1) etaMinutes = 1;

                var notif = new HospitalNotification
                {
                    HospitalId = h.Id,
                    EmergencyCaseId = ec.Id,
                    Status = AppConstants.CaseStatusPending,
                    DriverName = ec.Driver?.DriverName ?? "Unknown",
                    VehicleNo = ec.Driver?.Vehicle ?? "Unknown",
                    EtaMinutes = etaMinutes,
                    DriverLat = ec.PatientLat, // Lấy tạm tọa độ bệnh nhân làm vị trí xuất phát
                    DriverLng = ec.PatientLng,
                    CreatedAt = DateTime.UtcNow
                };
                _context.HospitalNotifications.Add(notif);

                incoming.Add((h.Id, etaMinutes));
            }

            // Lưu thông báo TRƯỚC khi phát tín hiệu: cổng bệnh viện nhận tín hiệu sẽ tải lại danh sách ngay,
            // nếu chưa lưu thì danh sách vẫn trống cho tới lần tải định kỳ sau.
            await _context.SaveChangesAsync();

            foreach (var (hospitalId, etaMinutes) in incoming)
            {
                // Phát tín hiệu SignalR tới Portal của từng bệnh viện trong nhóm
                await _hub.Clients.Group($"Hospital_{hospitalId}").SendAsync(AppConstants.SignalRReceiveIncomingPatient, new
                {
                    CaseId = ec.Id,
                    PatientName = ec.PatientProfile?.FullName ?? "Bệnh nhân",
                    EmergencyType = ec.EmergencyType,
                    EtaMinutes = etaMinutes,
                    DriverName = ec.Driver?.DriverName ?? "Unknown",
                    VehicleNo = ec.Driver?.Vehicle ?? "Unknown"
                });
            }

            // YÊU CẦU 13: Thông báo lại cho Driver để tắt trạng thái loading và hiển thị thông tin chờ đợi
            var driverConnId = AmbulanceHub.GetConnectionByUsername(ec.AssignedDriverUsername ?? "");
            if (!string.IsNullOrEmpty(driverConnId))
            {
                await _hub.Clients.Client(driverConnId).SendAsync("SuggestHospitals", nearbyHospitals.Select(h => new
                {
                    h.Id,
                    h.Name,
                    h.ReceptionStatus,
                    h.AvailableEmergencyBeds,
                    Distance = DistanceKm((double)ec.PatientLat, (double)ec.PatientLng, (double)h.Lat, (double)h.Lng)
                }).ToList());
            }
        }

        private async Task<List<Hospital>> GetHospitalsInRadius(decimal lat, decimal lng, double radiusKm)
        {
            // Tối ưu SQL: Sử dụng Bounding Box để lọc trước tọa độ tại Database
            const double earthRadiusKm = 6371.0;
            double latDelta = radiusKm / earthRadiusKm * (180.0 / Math.PI);
            double lngDelta = radiusKm / (earthRadiusKm * Math.Cos(Math.PI * (double)lat / 180.0)) * (180.0 / Math.PI);

            decimal minLat = lat - (decimal)latDelta;
            decimal maxLat = lat + (decimal)latDelta;
            decimal minLng = lng - (decimal)lngDelta;
            decimal maxLng = lng + (decimal)lngDelta;

            var nearbyHospitals = await _context.Hospitals
                .Where(h => h.IsActive && h.ReceptionStatus == AppConstants.HospitalReceptionOpen && h.AvailableEmergencyBeds > 0
                       && h.Lat >= minLat && h.Lat <= maxLat
                       && h.Lng >= minLng && h.Lng <= maxLng)
                .ToListAsync();

            return nearbyHospitals.Where(h => 
                DistanceKm((double)lat, (double)lng, (double)h.Lat, (double)h.Lng) <= radiusKm 
            ).ToList();
        }

        private async Task FinalizeTrip(EmergencyCase ec, double? distance, int? duration)
        {
            var driver = ec.Driver;
            
            // Lấy tên bệnh viện thực tế đã xác nhận tiếp nhận
            var hospitalName = "Bệnh viện tiếp nhận";
            if (ec.ConfirmedHospitalId.HasValue)
            {
                var hospital = await _context.Hospitals.FindAsync(ec.ConfirmedHospitalId.Value);
                if (hospital != null) hospitalName = hospital.Name;
            }

            // Cập nhật trạng thái tài xế về ONLINE để nhận ca mới
            if (driver != null) driver.Status = AppConstants.StatusOnline;
            
            // Cập nhật trạng thái ca cấp cứu trong Database
            ec.Status = AppConstants.CaseStatusCompleted;

            var history = new TripHistory
            { // "N/A" có thể coi là giá trị mặc định an toàn
                DriverName = driver?.DriverName ?? "N/A",
                VehicleNo = driver?.Vehicle ?? "N/A",
                HospitalName = hospitalName,
                PatientAddress = ec.PatientAddress,

                // Lưu dữ liệu thực tế từ OSRM phía Driver gửi lên
                DistanceKm = (decimal)(distance ?? 0), 
                DurationMinutes = duration ?? (int)(DateTime.UtcNow - ec.CreatedAt).TotalMinutes,
                TripStatus = AppConstants.CaseStatusCompleted,
                CreatedAt = ec.CreatedAt,
                CompletedAt = DateTime.UtcNow
            };
            _context.TripHistories.Add(history);
        }

        // ===================================================================
        // HELPER: Haversine distance km
        // ===================================================================
        private static double DistanceKm(double lat1, double lon1, double lat2, double lon2)
        {
            const double R = 6371;
            double dLat = DegreesToRadians(lat2 - lat1);
            double dLon = DegreesToRadians(lon2 - lon1);
            double a = Math.Sin(dLat / 2) * Math.Sin(dLat / 2) +
                       Math.Cos(DegreesToRadians(lat1)) * Math.Cos(DegreesToRadians(lat2)) *
                       Math.Sin(dLon / 2) * Math.Sin(dLon / 2);
            double c = 2 * Math.Atan2(Math.Sqrt(a), Math.Sqrt(1 - a));
            return R * c;
        }

        private async Task<List<Hospital>> GetTopNearestHospitals(decimal lat, decimal lng, int count)
        {
            // Tối ưu SQL: Chỉ lấy các bệnh viện trong phạm vi 15km để tính toán top, tránh load toàn bộ DB
            const double searchRadius = 15.0; 
            const double earthRadiusKm = 6371.0;
            double latDelta = searchRadius / earthRadiusKm * (180.0 / Math.PI);
            double lngDelta = searchRadius / (earthRadiusKm * Math.Cos(Math.PI * (double)lat / 180.0)) * (180.0 / Math.PI);

            decimal minLat = lat - (decimal)latDelta;
            decimal maxLat = lat + (decimal)latDelta;
            decimal minLng = lng - (decimal)lngDelta;
            decimal maxLng = lng + (decimal)lngDelta;

            var candidateHospitals = await _context.Hospitals
                .OrderBy(h => h.Id)
                .Where(h => h.IsActive && h.ReceptionStatus == AppConstants.HospitalReceptionOpen && h.AvailableEmergencyBeds > 0
                       && h.Lat >= minLat && h.Lat <= maxLat
                       && h.Lng >= minLng && h.Lng <= maxLng)
                .ToListAsync();
            return candidateHospitals.Select(h => new { 
                h, 
                dist = DistanceKm((double)lat, (double)lng, (double)h.Lat, (double)h.Lng) 
            })
            .OrderBy(x => x.dist)
            .Take(count)
            .Select(x => x.h)
            .ToList();
        }

        private static double DegreesToRadians(double degrees)
        {
            return degrees * Math.PI / 180.0;
        }
    }
}
