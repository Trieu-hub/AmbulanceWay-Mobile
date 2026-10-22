using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using AmbulanceWay.Data;
using Microsoft.AspNetCore.Authorization;
using System.Security.Claims;
using AmbulanceWay.Constants;
using System.IdentityModel.Tokens.Jwt;

namespace AmbulanceWay.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    [Authorize]
    public class TripsController : ControllerBase
    {
        private readonly AmbulanceWayDbContext _context;

        public TripsController(AmbulanceWayDbContext context)
        {
            _context = context;
        }

        [HttpPost]
        public async Task<IActionResult> CreateTrip([FromBody] AmbulanceWay.Models.AmbulanceTrip trip)
        {
            if (trip == null)
                return BadRequest(new { message = "Invalid data" });

            var username = User.FindFirst(ClaimTypes.Name)?.Value ?? "Unknown";
            var userIdStr = User.FindFirst("UserId")?.Value;
            
            var driver = await _context.Drivers.FirstOrDefaultAsync(d => d.UserId.ToString() == userIdStr);
            if (driver != null)
            {
                trip.StaffName = driver.DriverName;
                trip.VehicleNo = driver.Vehicle;
                trip.Hospital = driver.Station;
            }
            trip.ShiftStart = DateTime.UtcNow;

            trip.CreatedAt = DateTime.UtcNow;

            _context.AmbulanceTrips.Add(trip);
            await _context.SaveChangesAsync();

            return Ok(trip);
        }

        [HttpGet]
        public async Task<IActionResult> GetTrips()
        {
            var username = User.FindFirst(ClaimTypes.Name)?.Value;
            var trips = await _context.AmbulanceTrips
                .AsNoTracking()
                .Where(t => t.StaffName.Contains(username ?? "") || t.Status == "PENDING")
                .ToListAsync(); // TODO: Nên dùng hằng số cho "PENDING"
            return Ok(trips);
        }

        [HttpGet("assigned")]
        public async Task<IActionResult> GetAssignedTrips()
        {
            var username = User.FindFirst(ClaimTypes.Name)?.Value;
            var trips = await _context.AmbulanceTrips
                .AsNoTracking() // TODO: Nên dùng hằng số cho "COMPLETED"
                .Where(t => t.StaffName.Contains(username ?? "") && t.Status != "COMPLETED") // TODO: Nên dùng hằng số cho "COMPLETED"
                .ToListAsync();
            return Ok(trips);
        }

        [HttpPut("{id}/status")]
        public async Task<IActionResult> UpdateStatus(int id, [FromBody] string newStatus)
        {
            var trip = await _context.AmbulanceTrips.FindAsync(id);

            if (trip == null)
                return NotFound(new { message = "Trip not found" });

            if (string.IsNullOrWhiteSpace(newStatus))
                return BadRequest(new { message = "Invalid status" });

            trip.Status = newStatus;

            await _context.SaveChangesAsync();

            return Ok(new { success = true });
        }
    }
}