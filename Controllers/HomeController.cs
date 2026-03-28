using System.Diagnostics;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using AmbulanceWay.Models;
using AmbulanceWay.Data;

namespace AmbulanceWay.Controllers
{
    public class HomeController : Controller
    {
        private readonly AmbulanceWayDbContext _context;

        public HomeController(AmbulanceWayDbContext context)
        {
            _context = context;
        }
        public async Task<IActionResult> Index()
        {
            var driver = HttpContext.Session.GetString("DriverName");
            if (string.IsNullOrEmpty(driver))
            {
                return RedirectToAction("Login", "Account");
            }

            var trips = await _context.AmbulanceTrips
                .AsNoTracking()
                .Take(100)
                .ToListAsync();

            return View(trips);
        }

        public IActionResult Map()
        {
            var driver = HttpContext.Session.GetString("DriverName");

            if (driver == null)
            {
                 return RedirectToAction("Index");
            }

            return View();
        }
        [HttpPost]
        public async Task<IActionResult> Register(string username, string password)
        {
            if (string.IsNullOrEmpty(username) || string.IsNullOrEmpty(password))
                return Json(new { success = false, message = "Thiếu thông tin" });

            var user = await _context.Users
                .FirstOrDefaultAsync(x => x.Username == username);
            if (user == null)
            {
                user = new User
                {
                    Username = username,
                    PasswordHash = password,
                    RoleId = 1
                };

                _context.Users.Add(user);
                await _context.SaveChangesAsync();
            }
            return Json(new { success = true });
        }
        [HttpPost]
public async Task<IActionResult> Login(string driverName, string station, string vehicle)
{
    if (string.IsNullOrEmpty(driverName) 
        || string.IsNullOrEmpty(station) 
        || string.IsNullOrEmpty(vehicle))
    {
        return Json(new { success = false, message = "Thiếu thông tin" });
    }

    var user = await _context.Users
        .FirstOrDefaultAsync(x =>
            x.Username == driverName &&
            x.PasswordHash == station);

    if (user == null)
    {
        user = new User
        {
            Username = driverName,
            PasswordHash = station,
            RoleId = 1,
            Status = "ACTIVE",
            IsOnline = true
        };

        _context.Users.Add(user);
        await _context.SaveChangesAsync();
    }

    if (user.Status != "ACTIVE")
    {
        return Json(new { success = false, message = "Tài khoản bị khóa hoặc chưa duyệt!" });
    }

    HttpContext.Session.SetString("DriverName", user.Username);
    HttpContext.Session.SetString("Vehicle", vehicle);

    return Json(new { success = true });
}
        [HttpPost]
       public IActionResult EndShift()
       {
       return Json(new { success = true });
       }
        public IActionResult Privacy()
        {
            return View();
        }

        [ResponseCache(Duration = 0, Location = ResponseCacheLocation.None, NoStore = true)]
        public IActionResult Error()
        {
            return View(new ErrorViewModel
            {
                RequestId = Activity.Current?.Id ?? HttpContext.TraceIdentifier
            });
        }
    }
}