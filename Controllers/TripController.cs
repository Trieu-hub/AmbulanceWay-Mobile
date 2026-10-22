using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using AmbulanceWay.Models;
using AmbulanceWay.Hubs;
using AmbulanceWay.Constants;
using AmbulanceWay.Data;
using Microsoft.EntityFrameworkCore;

namespace AmbulanceWay.Controllers
{
    public class TripController : Controller
    {
        private readonly AmbulanceWayDbContext _context;
        private readonly IHubContext<AmbulanceHub> _hubContext;

        public TripController(AmbulanceWayDbContext context, IHubContext<AmbulanceHub> hubContext)
        {
            _context = context;
            _hubContext = hubContext;
        }

        // API để Admin nhấn nút "Điều phối" từ giao diện
        [HttpPost]
        public async Task<IActionResult> CreateDispatch([FromBody] AmbulanceTrip trip)
        {
            if (trip == null) return BadRequest("Dữ liệu không hợp lệ");

            try 
            {
                // 1. Thiết lập các giá trị mặc định cho chuyến đi mới
                trip.Status = AppConstants.CaseStatusAssigned; // Sử dụng hằng số
                trip.CreatedAt = DateTime.UtcNow; // Sử dụng UtcNow
                trip.ShiftStart = DateTime.UtcNow; // Sử dụng UtcNow

                // 2. Lưu vào Database
                _context.AmbulanceTrips.Add(trip);
                await _context.SaveChangesAsync();

                // 3. Gửi lệnh Real-time qua SignalR
                await _hubContext.Clients.All.SendAsync(AppConstants.SignalRReceiveNewTrip, new {
                    TripId = trip.Id,
                    StaffName = trip.StaffName,
                    Address = trip.IncidentAddress,
                    Hospital = trip.Hospital,
                    Lat = trip.IncidentLat,
                    Lng = trip.IncidentLng,
                    CaseId = 0 // Gán mặc định cho ca điều phối thủ công
                });

                return Ok(new { success = true, message = "Đã gửi lệnh điều phối!", tripId = trip.Id });
            }
            catch (Exception ex)
            {
                return StatusCode(500, $"Lỗi hệ thống: {ex.Message}");
            }
        }
    }
}
