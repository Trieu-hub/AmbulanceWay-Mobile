using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using AmbulanceWay.Data;
using AmbulanceWay.Models;
using AmbulanceWay.Constants;

namespace AmbulanceWay.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    [JwtOrAdminSession] // App mobile (JWT) và trang Admin web (Session) đều gọi
    public class TripHistoryController : ControllerBase
    {
        private readonly AmbulanceWayDbContext _context;

        public TripHistoryController(AmbulanceWayDbContext context)
        {
            _context = context;
        }

        // GET /api/TripHistory - Lấy danh sách lịch sử chuyến đi
        [HttpGet]
        public async Task<IActionResult> GetAll([FromQuery] int page = 1, [FromQuery] int pageSize = 20)
        {
            var query = _context.TripHistories
                .OrderByDescending(t => t.CreatedAt)
                .Skip((page - 1) * pageSize)
                .Take(pageSize);

var data = await query.Select(t => new
                {
                t.Id,
                t.DriverName,
                t.VehicleNo,
                t.HospitalName,
                t.PatientAddress,
                t.DistanceKm,
                t.DurationMinutes,
                t.TripStatus,
                t.OverallRating,
                t.TimeRating,
                t.AttitudeRating,
                t.VehicleRating,
                t.SituationRating,
                t.DriverNote,
                createdAt = t.CreatedAt,
                completedAt = t.CompletedAt
            }).ToListAsync();

            var total = await _context.TripHistories.CountAsync();

            return Ok(new { data, total, page, pageSize });
        }

        // GET /api/TripHistory/stats - Thống kê tổng quan
        [HttpGet("stats")]
        public async Task<IActionResult> GetStats()
        {
            var totalTrips = await _context.TripHistories.CountAsync();
            var totalDistance = await _context.TripHistories.SumAsync(t => t.DistanceKm);
            var avgDuration = await _context.TripHistories.AverageAsync(t => (decimal?)t.DurationMinutes) ?? 0;

            // Top 5 bệnh viện được chọn nhiều nhất
            var topHospitals = await _context.TripHistories
                .GroupBy(t => t.HospitalName)
                .Select(g => new { hospitalName = g.Key, count = g.Count() })
                .OrderByDescending(x => x.count)
                .Take(5)
                .ToListAsync();

            // Top 5 tài xế hoạt động nhiều nhất
            var topDrivers = await _context.TripHistories
                .GroupBy(t => t.DriverName)
                .Select(g => new { driverName = g.Key, count = g.Count() })
                .OrderByDescending(x => x.count)
                .Take(5)
                .ToListAsync();

            return Ok(new
            {
                totalTrips,
                totalDistanceKm = Math.Round(totalDistance, 2),
                avgDurationMinutes = Math.Round(avgDuration, 1),
                topHospitals,
                topDrivers
            });
        }

        // POST /api/TripHistory - Lưu chuyến đi mới (được gọi khi complete trip)
        [HttpPost]
        public async Task<IActionResult> Create([FromBody] TripHistory trip)
        {
            if (trip == null) return BadRequest("Dữ liệu trống");

            trip.CreatedAt = DateTime.UtcNow;
            if (trip.TripStatus == AppConstants.CaseStatusCompleted)
            {
                trip.CompletedAt = DateTime.UtcNow;
            }

            _context.TripHistories.Add(trip);
            await _context.SaveChangesAsync();

            return Ok(new { success = true, id = trip.Id, message = "Lưu lịch sử chuyến đi thành công" });
        }


        // GET /api/TripHistory/search - Tìm kiếm theo từ khóa với phân trang
        [HttpGet("search")]
        public async Task<IActionResult> Search([FromQuery] string? keyword, [FromQuery] int page = 1, [FromQuery] int pageSize = 50)
        {
            var query = _context.TripHistories.AsQueryable();

            if (!string.IsNullOrEmpty(keyword))
            {
                keyword = keyword.ToLower();
                query = query.Where(t => 
                    t.DriverName.ToLower().Contains(keyword) ||
                    t.VehicleNo.ToLower().Contains(keyword) ||
                    t.HospitalName.ToLower().Contains(keyword) ||
                    t.PatientAddress.ToLower().Contains(keyword));
            }

            var total = await query.CountAsync();
            var data = await query
                .OrderByDescending(t => t.CreatedAt)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .Select(t => new
                {
                    t.Id,
                    t.DriverName,
                    t.VehicleNo,
                    t.HospitalName,
                    t.PatientAddress,
                    t.DistanceKm,
                    t.DurationMinutes,
                    t.TripStatus,
                    t.OverallRating,
                    t.TimeRating,
                    t.AttitudeRating,
                    t.VehicleRating,
                    t.SituationRating,
                    t.DriverNote,
                    createdAt = t.CreatedAt.ToString("dd/MM/yyyy HH:mm")
                })
                .ToListAsync();

            return Ok(new { data, total, page, pageSize });
        }
    }
}
