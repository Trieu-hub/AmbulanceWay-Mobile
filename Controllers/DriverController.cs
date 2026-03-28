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
            _context.Update(driver);
            _context.SaveChanges();

            return RedirectToAction("Profile", new { id = driver.Id });
        }
        public IActionResult Profile(int id)
{
    var driver = _context.Drivers.Find(id);
    return View(driver);
}
    }
}