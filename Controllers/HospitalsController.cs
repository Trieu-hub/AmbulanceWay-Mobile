using AmbulanceWay.Data;
using AmbulanceWay.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
 
namespace AmbulanceWay.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    [JwtOrAdminSession] // App mobile (JWT) và trang Admin web (Session) đều gọi
    public class HospitalsController : ControllerBase
    {
        private readonly AmbulanceWayDbContext _context;
 
        public HospitalsController(AmbulanceWayDbContext context)
        {
            _context = context;
        }
 
        // GET /api/Hospitals
        [HttpGet]
        public async Task<IActionResult> GetAll()
        {
            var hospitals = await _context.Hospitals
                .Where(h => h.IsActive)
                .Select(h => new
                {
                    h.Id, h.Name, h.Address, h.Lat, h.Lng, h.Phone, h.Type,
                    h.TotalEmergencyBeds, h.AvailableEmergencyBeds,
                    h.ReceptionStatus, h.StatusNote, h.StatusUpdatedAt
                })
                .ToListAsync();
            return Ok(hospitals);
        }
 
        // GET /api/Hospitals/nearby?lat=...&lng=...&radiusKm=10
        [HttpGet("nearby")]
        public async Task<IActionResult> GetNearby(decimal lat, decimal lng, decimal? radiusKm = 10)
        {
            var hospitals = await _context.Hospitals
                .Where(h => h.IsActive)
                .Select(h => new
                {
                    h.Id, h.Name, h.Address, h.Lat, h.Lng, h.Phone, h.Type,
                    h.TotalEmergencyBeds, h.AvailableEmergencyBeds,
                    h.ReceptionStatus, h.StatusNote,
                    distanceKm = (decimal)Math.Sqrt(
                        Math.Pow((double)(h.Lat - lat), 2)
                        + Math.Pow((double)(h.Lng - lng) * (double)(111.32m * (decimal)Math.Cos((double)lat * Math.PI / 180)), 2)
                    )
                })
                .OrderBy(h => h.distanceKm)
                .Take(10)
                .ToListAsync();
 
            return Ok(hospitals);
        }
 
        // GET /api/Hospitals/available?lat=...&lng=...  — Chỉ BV còn nhận bệnh
        [HttpGet("available")]
        public async Task<IActionResult> GetAvailable(decimal lat, decimal lng)
        {
            var hospitals = await _context.Hospitals
                .Where(h => h.IsActive && h.ReceptionStatus == "OPEN")
                .Select(h => new
                {
                    h.Id, h.Name, h.Address, h.Lat, h.Lng, h.Phone,
                    h.AvailableEmergencyBeds, h.ReceptionStatus, h.StatusNote,
                    distanceKm = (decimal)Math.Sqrt(
                        Math.Pow((double)(h.Lat - lat), 2)
                        + Math.Pow((double)(h.Lng - lng) * (double)(111.32m * (decimal)Math.Cos((double)lat * Math.PI / 180)), 2)
                    )
                })
                .OrderBy(h => h.distanceKm)
                .Take(5)
                .ToListAsync();
 
            return Ok(hospitals);
        }
 
        // POST /api/Hospitals
        [HttpPost]
        public async Task<IActionResult> Create([FromBody] Hospital hospital)
        {
            if (hospital == null) return BadRequest("Dữ liệu trống");
            if (string.IsNullOrEmpty(hospital.Name)) return BadRequest("Tên bệnh viện là bắt buộc");
 
            hospital.IsActive = true;
            hospital.ReceptionStatus = "OPEN";
            _context.Hospitals.Add(hospital);
            await _context.SaveChangesAsync(); // TODO: Nên dùng hằng số cho "OPEN"
            return Ok(new { success = true, id = hospital.Id });
        }
 
        // PUT /api/Hospitals/{id}
        [HttpPut("{id}")]
        public async Task<IActionResult> Update(int id, [FromBody] Hospital hospital)
        {
            var existing = await _context.Hospitals.FindAsync(id);
            if (existing == null) return NotFound("Không tìm thấy bệnh viện");
 
            existing.Name = hospital.Name;
            existing.Address = hospital.Address;
            existing.Lat = hospital.Lat;
            existing.Lng = hospital.Lng;
            existing.Phone = hospital.Phone;
            existing.Type = hospital.Type;
            existing.IsActive = hospital.IsActive;
            // Cập nhật thêm field mới
            existing.TotalEmergencyBeds = hospital.TotalEmergencyBeds;
            existing.AvailableEmergencyBeds = hospital.AvailableEmergencyBeds;
            existing.ReceptionStatus = hospital.ReceptionStatus;
            existing.StatusNote = hospital.StatusNote;
 
            await _context.SaveChangesAsync();
            return Ok(new { success = true });
        }
 
        // DELETE /api/Hospitals/{id}  — Soft delete
        [HttpDelete("{id}")]
        public async Task<IActionResult> Delete(int id)
        {
            var hospital = await _context.Hospitals.FindAsync(id);
            if (hospital == null) return NotFound("Không tìm thấy bệnh viện");
            hospital.IsActive = false;
            await _context.SaveChangesAsync();
            return Ok(new { success = true });
        }
    }
}