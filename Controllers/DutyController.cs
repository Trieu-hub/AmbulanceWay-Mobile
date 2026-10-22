using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using AmbulanceWay.Data;
using AmbulanceWay.Models;
using System.Security.Claims;

namespace AmbulanceWay.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    [Authorize] // Require JWT token
    public class DutyController : ControllerBase
    {
        private readonly AmbulanceWayDbContext _context;

        public DutyController(AmbulanceWayDbContext context)
        {
            _context = context;
        }

        [HttpPost("start")]
        public async Task<IActionResult> StartDuty([FromBody] StartDutyRequest request)
        {
            var username = User.FindFirst(ClaimTypes.Name)?.Value;
            if (string.IsNullOrEmpty(username))
                return Unauthorized(new { message = "Invalid token" });

            // Check if already on duty
            var activeDuty = await _context.DutySessions
                .FirstOrDefaultAsync(d => d.Username == username && d.EndTime == null);
            if (activeDuty != null)
                return BadRequest(new { message = "Already on active duty" });

            var duty = new DutySession
            {
                HospitalName = request.HospitalName,
                StaffName = request.StaffName,
                VehicleNo = request.VehicleNo,
                Username = username,
                StartTime = DateTime.UtcNow
            };

            _context.DutySessions.Add(duty);
            await _context.SaveChangesAsync();

            return Ok(new { success = true, dutyId = duty.Id, message = "Duty started" });
        }

        [HttpPost("end")]
        public async Task<IActionResult> EndDuty()
        {
            var username = User.FindFirst(ClaimTypes.Name)?.Value;
            if (string.IsNullOrEmpty(username))
                return Unauthorized(new { message = "Invalid token" });

            var activeDuty = await _context.DutySessions
                .FirstOrDefaultAsync(d => d.Username == username && d.EndTime == null);
            if (activeDuty == null)
                return BadRequest(new { message = "No active duty found" });

            activeDuty.EndTime = DateTime.UtcNow;
            await _context.SaveChangesAsync();

            return Ok(new { success = true, message = "Duty ended" });
        }

        [HttpGet("current")]
        public async Task<IActionResult> GetCurrentDuty()
        {
            var username = User.FindFirst(ClaimTypes.Name)?.Value;
            if (string.IsNullOrEmpty(username))
                return Unauthorized(new { message = "Invalid token" });

            var duty = await _context.DutySessions
                .FirstOrDefaultAsync(d => d.Username == username && d.EndTime == null);

            if (duty == null) return Ok(new { onDuty = false });

            return Ok(new {
                onDuty = true,
                duty = new {
                    id = duty.Id,
                    hospitalName = duty.HospitalName,
                    vehicleNo = duty.VehicleNo,
                    startTime = duty.StartTime,
                    duration = DateTime.UtcNow - duty.StartTime
                }
            });
        }
    }

    public class StartDutyRequest
    {
        public string HospitalName { get; set; } = "";
        public string StaffName { get; set; } = "";
        public string VehicleNo { get; set; } = "";
    }
}
