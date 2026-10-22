using AmbulanceWay.Data;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using AmbulanceWay.Models;
using Microsoft.EntityFrameworkCore;
 
using AmbulanceWay.Constants;

namespace AmbulanceWay.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class PatientRatingController : ControllerBase
    {
        private readonly AmbulanceWayDbContext _context;
 
        public PatientRatingController(AmbulanceWayDbContext context)
        {
            _context = context;
        }
 
        // ===================================================================
        // POST /api/PatientRating  — Bệnh nhân gửi đánh giá
        // ===================================================================
        public class SubmitRatingRequest
        {
            public int EmergencyCaseId { get; set; }
            public int PatientProfileId { get; set; }
            public int OverallRating { get; set; }
            public int ResponseTimeRating { get; set; }
            public int DriverAttitudeRating { get; set; }
            public int VehicleConditionRating { get; set; }
            public int SituationHandlingRating { get; set; }
            public string? Comment { get; set; }
        }
 
        [HttpPost]
        public async Task<IActionResult> Submit([FromBody] SubmitRatingRequest req)
        {
            if (req == null) return BadRequest(new { message = "Dữ liệu trống" });
 
            // Kiểm tra ca có tồn tại và thuộc bệnh nhân này
            var ec = await _context.EmergencyCases
                .FirstOrDefaultAsync(e => e.Id == req.EmergencyCaseId
                                       && e.PatientProfileId == req.PatientProfileId);
            if (ec == null)
                return NotFound(new { message = "Không tìm thấy ca hoặc bạn không có quyền đánh giá" });
 
            if (ec.Status != AppConstants.CaseStatusCompleted)
                return BadRequest(new { message = "Ca chưa hoàn thành, chưa thể đánh giá" });
 
            // Kiểm tra đã đánh giá chưa
            var existed = await _context.PatientRatings
                .AnyAsync(r => r.EmergencyCaseId == req.EmergencyCaseId);
            if (existed)
                return BadRequest(new { message = "Ca này đã được đánh giá rồi" });
 
            // Validate điểm 1-5
            var scores = new[] { req.OverallRating, req.ResponseTimeRating, req.DriverAttitudeRating,
                                  req.VehicleConditionRating, req.SituationHandlingRating };
            if (scores.Any(s => s < 1 || s > 5))
                return BadRequest(new { message = "Điểm đánh giá phải từ 1 đến 5" });
 
            var rating = new PatientRating
            {
                EmergencyCaseId = req.EmergencyCaseId,
                PatientProfileId = req.PatientProfileId,
                OverallRating = req.OverallRating,
                ResponseTimeRating = req.ResponseTimeRating,
                DriverAttitudeRating = req.DriverAttitudeRating,
                VehicleConditionRating = req.VehicleConditionRating,
                SituationHandlingRating = req.SituationHandlingRating,
                Comment = req.Comment,
                CreatedAt = DateTime.UtcNow // Sử dụng UtcNow
            };
            _context.PatientRatings.Add(rating);
            await _context.SaveChangesAsync();
 
            return Ok(new { success = true, ratingId = rating.Id, message = "Cảm ơn bạn đã đánh giá!" });
        }
 
        // ===================================================================
        // GET /api/PatientRating/case/{caseId}  — Lấy đánh giá theo ca
        // ===================================================================
        [HttpGet("case/{caseId}")]
        public async Task<IActionResult> GetByCase(int caseId)
        {
            var rating = await _context.PatientRatings
                .AsNoTracking()
                .FirstOrDefaultAsync(r => r.EmergencyCaseId == caseId);
 
            if (rating == null) return NotFound(new { message = "Chưa có đánh giá" });
            return Ok(rating);
        }
 
        // ===================================================================
        // GET /api/PatientRating/stats  — Thống kê đánh giá (admin)
        // ===================================================================
        [HttpGet("stats")]
        public async Task<IActionResult> GetStats([FromQuery] DateTime? from, [FromQuery] DateTime? to)
        {
            var query = _context.PatientRatings.AsQueryable();
            if (from.HasValue) query = query.Where(r => r.CreatedAt >= from.Value);
            if (to.HasValue) query = query.Where(r => r.CreatedAt <= to.Value);
 
            var total = await query.CountAsync();
            if (total == 0)
                return Ok(new { total = 0, message = "Chưa có dữ liệu đánh giá" });
 
            var stats = await query.GroupBy(r => 1).Select(g => new
            {
                total = g.Count(),
                avgOverall = Math.Round((double)g.Average(r => r.OverallRating), 1),
                avgResponseTime = Math.Round((double)g.Average(r => r.ResponseTimeRating), 1),
                avgDriverAttitude = Math.Round((double)g.Average(r => r.DriverAttitudeRating), 1),
                avgVehicle = Math.Round((double)g.Average(r => r.VehicleConditionRating), 1),
                avgHandling = Math.Round((double)g.Average(r => r.SituationHandlingRating), 1),
                satisfiedCount = g.Count(r => r.OverallRating >= 4),
            }).FirstAsync();
 
            return Ok(new
            {
                stats.total,
                stats.avgOverall,
                stats.avgResponseTime,
                stats.avgDriverAttitude,
                stats.avgVehicle,
                stats.avgHandling,
                satisfiedPercent = Math.Round((double)stats.satisfiedCount / stats.total * 100, 1),
                // Phân bố điểm 1-5
                distribution = await query
                    .GroupBy(r => r.OverallRating)
                    .Select(g => new { score = g.Key, count = g.Count() })
                    .OrderBy(x => x.score)
                    .ToListAsync()
            });
        }
 
        // ===================================================================
        // GET /api/PatientRating/check/{caseId}/{patientProfileId}
        // Kiểm tra bệnh nhân đã đánh giá chưa (để UI ẩn/hiện form)
        // ===================================================================
        [HttpGet("check/{caseId}/{patientProfileId}")]
        public async Task<IActionResult> Check(int caseId, int patientProfileId)
        {
            var hasRated = await _context.PatientRatings
                .AnyAsync(r => r.EmergencyCaseId == caseId && r.PatientProfileId == patientProfileId);
            return Ok(new { hasRated });
        }
    }
}