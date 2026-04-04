using Microsoft.AspNetCore.Mvc;
using AmbulanceWay.Models;
using AmbulanceWay.Data;

namespace AmbulanceWay.Controllers
{
    public class DriverController : Controller
    {
        private readonly AmbulanceWayDbContext _context;

        public DriverController(AmbulanceWayDbContext context)
        {
            _context = context;
        }

        [HttpPost]
        public IActionResult Update(Driver driver)
        {
            if (driver == null)
                return BadRequest();

            var existing = _context.Drivers.Find(driver.Id);

            if (existing == null)
                return NotFound();

            existing.DriverName = driver.DriverName;
            existing.Phone = driver.Phone;
            existing.Vehicle = driver.Vehicle;
            existing.Station = driver.Station;

            _context.SaveChanges();

            return RedirectToAction("Profile", new { id = driver.Id });
        }

        public IActionResult Profile(int id)
        {
            var driver = _context.Drivers.Find(id);

            if (driver == null)
                return NotFound();

            var role = HttpContext.Session.GetInt32("ROLE");

            if (role != null && role == 1)
            {
                return View("Edit", driver);
            }

            return View("Profile", driver);
        }
    }
}