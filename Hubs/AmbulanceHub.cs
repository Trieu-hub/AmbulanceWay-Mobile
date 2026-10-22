using Microsoft.AspNetCore.SignalR;
using System.Collections.Concurrent;
using AmbulanceWay.Constants; // Import AppConstants
 
namespace AmbulanceWay.Hubs
{
    public class AmbulanceHub : Hub
    {
        // Cache vị trí realtime của tài xế (key = username)
        private static readonly ConcurrentDictionary<string, DriverLocationCacheItem> DriverLocations
            = new(StringComparer.OrdinalIgnoreCase);
 
        // Map connectionId -> username (để gửi đến đúng tài xế)
        private static readonly ConcurrentDictionary<string, string> ConnectionToUsername
            = new(StringComparer.OrdinalIgnoreCase);
 
        // Map username -> connectionId
        private static readonly ConcurrentDictionary<string, string> UsernameToConnection
            = new(StringComparer.OrdinalIgnoreCase);
 
        // Map hospitalId -> connectionId (portal bệnh viện)
        private static readonly ConcurrentDictionary<string, string> HospitalConnections
            = new(StringComparer.OrdinalIgnoreCase);
 
        // Lưu danh sách SOS đang chờ để tính Escalation (Key: CaseId, Value: CreatedTime)
        public static readonly ConcurrentDictionary<int, DateTime> PendingCases = new();

        public class DriverLocationCacheItem
        {
            public double Lat { get; set; }
            public double Lng { get; set; }
            public DateTime UpdatedAtUtc { get; set; }
        }

        /// <summary>
        /// Lấy toàn bộ bản sao danh sách vị trí tài xế để phục vụ tính toán khoảng cách
        /// </summary>
        public static IReadOnlyDictionary<string, DriverLocationCacheItem> GetDriverLocations() 
            => DriverLocations.ToDictionary(k => k.Key, v => v.Value);
 
        // ===================================================================
        // ĐĂNG KÝ KẾT NỐI
        // ===================================================================
 
        /// <summary>Tài xế đăng ký khi mở app (gọi sau khi connect)</summary>
        public async Task RegisterDriver(string username)
        {
            if (string.IsNullOrWhiteSpace(username)) return;
 
            ConnectionToUsername[Context.ConnectionId] = username;
            UsernameToConnection[username] = Context.ConnectionId;
 
            // Thêm vào group "Drivers" để admin có thể broadcast
            await Groups.AddToGroupAsync(Context.ConnectionId, AppConstants.RoleDriversGroup); // Sử dụng hằng số
            await Groups.AddToGroupAsync(Context.ConnectionId, $"Driver_{username}");
        }
 
        /// <summary>Portal bệnh viện đăng ký theo hospitalId</summary>
        public async Task RegisterHospital(int hospitalId)
        {
            var key = hospitalId.ToString();
            HospitalConnections[key] = Context.ConnectionId;
            await Groups.AddToGroupAsync(Context.ConnectionId, $"Hospital_{key}");
        }
 
        /// <summary>Admin đăng ký vào group admin</summary>
        public async Task RegisterAdmin()
        {   // Sử dụng hằng số
            await Groups.AddToGroupAsync(Context.ConnectionId, AppConstants.RoleAdminsGroup);
        }
 
        // ===================================================================
        // GPS - CẬP NHẬT VỊ TRÍ
        // ===================================================================
 
        /// <summary>Tài xế gọi định kỳ (~5 giây) để cập nhật tọa độ</summary>
        public async Task SendLocationUpdate(string username, double lat, double lng)
        {
            var now = DateTime.UtcNow;
            if (!string.IsNullOrWhiteSpace(username))
            {
                DriverLocations[username] = new DriverLocationCacheItem
                {
                    Lat = lat,
                    Lng = lng,
                    UpdatedAtUtc = now
                };
            }
 
            // Broadcast cho admin xem bản đồ
            await Clients.Group(AppConstants.RoleAdminsGroup).SendAsync("DriverLocationUpdate", new // Sử dụng hằng số
            {
                Username = username,
                Lat = lat,
                Lng = lng,
                Timestamp = now
            });
        }
 
        public static bool TryGetDriverLocation(string username, out DriverLocationCacheItem item)
            => DriverLocations.TryGetValue(username, out item!);

        // Đăng ký nhận cập nhật cho ca cấp cứu cụ thể (bệnh nhân dùng)
        public async Task JoinCase(int caseId)
        {
            await Groups.AddToGroupAsync(Context.ConnectionId, $"Case_{caseId}");
        }

        // Tài xế phát vị trí trực tiếp cho ca cấp cứu đó để bệnh nhân xem trên bản đồ
        public async Task SendDriverLocationToCase(int caseId, string username, double lat, double lng)
        {
            await Clients.Group($"Case_{caseId}").SendAsync("DriverLocationUpdate", new
            {
                Username = username,
                Lat = lat,
                Lng = lng,
                Timestamp = DateTime.UtcNow
            });
        }
 
        // ===================================================================
        // SOS - ĐIỀU PHỐI
        // ===================================================================
 
        /// <summary>Backend gọi để gửi SOS đến tài xế cụ thể theo username</summary>
        public static string? GetConnectionByUsername(string username)
            => UsernameToConnection.TryGetValue(username, out var connId) ? connId : null;
 
        /// <summary>Tài xế bấm "Nhận cuốc" - gửi signal lên server</summary>
        public async Task DriverAcceptCase(string driverUsername, int caseId)
        {
            // Đảm bảo cache connection luôn mới nhất khi tài xế tương tác
            if (!string.IsNullOrEmpty(driverUsername))
            {
                ConnectionToUsername[Context.ConnectionId] = driverUsername;
                UsernameToConnection[driverUsername] = Context.ConnectionId;
                PendingCases.TryRemove(caseId, out _);
            }

            // Thông báo cho admin
            await Clients.Group(AppConstants.RoleAdminsGroup).SendAsync("NotifyCaseAccepted", new // Sử dụng hằng số
            {
                Driver = driverUsername,
                CaseId = caseId, // TODO: Nên dùng hằng số cho "NotifyCaseAccepted"
                AcceptedAt = DateTime.UtcNow // Sử dụng UtcNow
            });
 
            // Thông báo cho các tài xế khác để họ ẩn popup SOS này
            await Clients.Group(AppConstants.RoleDriversGroup).SendAsync("CaseAlreadyTaken", new // Sử dụng hằng số
            {
                CaseId = caseId,
                TakenBy = driverUsername
            });
        }
 
        /// <summary>Tài xế cập nhật trạng thái chuyến (PICKED_UP, DELIVERING, COMPLETED)</summary>
        public async Task UpdateTripStatus(int caseId, string status, string driverUsername, object? extraData = null)
        {   // Sử dụng hằng số
            await Clients.Group(AppConstants.RoleAdminsGroup).SendAsync("TripStatusUpdated", new // "TripStatusUpdated" có thể là hằng số
            {
                CaseId = caseId,
                Status = status,
                Driver = driverUsername,
                Extra = extraData,
                UpdatedAt = DateTime.UtcNow // Sử dụng UtcNow
            });
        }

        /// <summary>Tài xế gửi cập nhật khoảng cách và thời gian thực tế từ OSRM</summary>
        public async Task SendEtaUpdate(int caseId, double distanceKm, int durationMinutes)
        {
            var payload = new {
                CaseId = caseId,
                DistanceKm = distanceKm,
                DurationMinutes = durationMinutes
            };
            await Clients.Group($"Case_{caseId}").SendAsync("EtaUpdated", payload);
            await Clients.Group(AppConstants.RoleAdminsGroup).SendAsync("EtaUpdated", payload);
        }
 
        // ===================================================================
        // BỆNH VIỆN - TÍN HIỆU TIẾP NHẬN
        // ===================================================================
 
        /// <summary>
        /// Khi bệnh viện xác nhận/từ chối, gửi thông báo về cho tài xế
        /// </summary>
        public async Task HospitalRespond(int notificationId, string status, string? room, string driverUsername)
        {
            // Tìm connection của tài xế
            if (UsernameToConnection.TryGetValue(driverUsername, out var connId))
            {
                await Clients.Client(connId).SendAsync("HospitalConfirmed", new // "HospitalConfirmed" có thể là hằng số
                {
                    NotificationId = notificationId,
                    Status = status,        // CONFIRMED / REJECTED
                    AssignedRoom = room,
                    RespondedAt = DateTime.UtcNow // Sử dụng UtcNow
                });
            }
        }
 
        // ===================================================================
        // CLEANUP KHI DISCONNECT
        // ===================================================================
 
        public override async Task OnDisconnectedAsync(Exception? exception)
        {
            if (ConnectionToUsername.TryRemove(Context.ConnectionId, out var username))
            {
                UsernameToConnection.TryRemove(username, out _);
            }
 
            // Xóa hospital connection nếu có
            var hospitalKey = HospitalConnections
                .FirstOrDefault(x => x.Value == Context.ConnectionId).Key;
            if (hospitalKey != null)
                HospitalConnections.TryRemove(hospitalKey, out _);
 
            await base.OnDisconnectedAsync(exception);
        }
 
        // ===================================================================
        // LEGACY - Giữ nguyên để không phá flow cũ
        // ===================================================================
 
        public async Task SendEmergencyCall(object emergencyData) // "ReceiveEmergencyCall" có thể là hằng số
            => await Clients.All.SendAsync("ReceiveEmergencyCall", emergencyData); 
 
        public async Task DispatchTripToDriver(string driverUsername, object tripData) // "ReceiveNewTrip" có thể là hằng số
            => await Clients.All.SendAsync("ReceiveNewTrip", new { TargetDriver = driverUsername, Data = tripData }); 

        // Gửi riêng 1 event tới đúng 1 tài xế (theo username)
        public static async Task SendToDriver(string driverUsername, string eventName, object payload, IHubContext<AmbulanceHub> hub)
        {
            if (string.IsNullOrWhiteSpace(driverUsername)) return;
            if (!UsernameToConnection.TryGetValue(driverUsername, out var connectionId)) return;

            await hub.Clients.Client(connectionId).SendAsync(eventName, payload);
        }
    }
}
