using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using AmbulanceWay.Models;
using AmbulanceWay.Data;  

namespace AmbulanceWay.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class TripsController : ControllerBase
    {
        private readonly AmbulanceWayDbContext _context;

        public TripsController(AmbulanceWayDbContext context)
        {
            _context = context;
        }
        [HttpPost]
public async Task<IActionResult> CreateTrip([FromBody] AmbulanceTrip trip)
{

    trip.StaffName = HttpContext.Session.GetString("STAFF") ?? "Unknown";
    trip.Hospital = HttpContext.Session.GetString("HOSPITAL") ?? "Unknown";
    trip.VehicleNo = HttpContext.Session.GetString("VEHICLE") ?? "Unknown";

    trip.CreatedAt = DateTime.Now;
    var shiftStartStr = HttpContext.Session.GetString("SHIFT_START");
    if (DateTime.TryParse(shiftStartStr, out DateTime shiftStart))
    {
        trip.ShiftStart = shiftStart;
    }
    else
    {
        trip.ShiftStart = DateTime.Now;
    }

    trip.CreatedAt = DateTime.Now;

    _context.AmbulanceTrips.Add(trip);
    await _context.SaveChangesAsync();

    return Ok(trip);
}

        [HttpGet]
        public async Task<IActionResult> GetTrips()
        {
            return Ok(await _context.AmbulanceTrips.ToListAsync());
        }
      [HttpPut("{id}/status")]
    public async Task<IActionResult> UpdateStatus(int id, [FromBody] string newStatus)
    {
        var trip = await _context.AmbulanceTrips.FindAsync(id);

        if (trip == null)
            return NotFound(new { message = "Trip not found" });

        trip.Status = newStatus;

        await _context.SaveChangesAsync();

        return Ok(new { success = true });
    }
    }
}
