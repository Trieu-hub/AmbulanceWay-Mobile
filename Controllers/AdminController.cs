using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using AmbulanceWay.Data;
using AmbulanceWay.Models;

namespace AmbulanceWay.Controllers
{
    public class AdminController : Controller
    {
        private readonly AmbulanceWayDbContext _context;
        public AdminController(AmbulanceWayDbContext context)
        {
            _context = context;
        }

        public async Task<IActionResult> Index()
        {
            var role = HttpContext.Session.GetInt32("ROLE");
            if (role != 1)
                return RedirectToAction("Login", "Account");

            var users = await _context.Users
                .Include(u => u.Role)
                .AsNoTracking()
                .ToListAsync();

            return View(users);
        }
    }
}