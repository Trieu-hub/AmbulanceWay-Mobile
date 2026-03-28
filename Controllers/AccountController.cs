using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Http;

namespace AmbulanceWay.Controllers
{
    public class AccountController : Controller
    {
        [HttpGet]
        public IActionResult Login()
        {
            return View();
        }

        [HttpPost]
        public IActionResult LoginAjax([FromBody] DutyLoginModel model)
        {
            if (string.IsNullOrWhiteSpace(model.HospitalName) ||
                string.IsNullOrWhiteSpace(model.StaffName))
            {
                return Json(new { success = false, message = "Thiếu thông tin ca trực" });
            }

            HttpContext.Session.SetString("HOSPITAL", model.HospitalName);
            HttpContext.Session.SetString("STAFF", model.StaffName);
            HttpContext.Session.SetString("VEHICLE", model.VehicleNo);
            HttpContext.Session.SetString(
                 "SHIFT_START",
                  DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss")
            );

            return Json(new { success = true });
        }

        public IActionResult Logout()
{
    var staff = HttpContext.Session.GetString("STAFF");
    var hospital = HttpContext.Session.GetString("HOSPITAL");
    var phone = HttpContext.Session.GetString("PHONE");
    var shiftStartStr = HttpContext.Session.GetString("SHIFT_START");

     DateTime shiftStart;
    if (!DateTime.TryParse(shiftStartStr, out shiftStart))
    {
        shiftStart = DateTime.Now;
    }

    DateTime shiftEnd = DateTime.Now;

    System.Diagnostics.Debug.WriteLine(
        $"LOGOUT: STAFF={staff}, HOSPITAL={hospital}, START={shiftStart}, END={shiftEnd}"
    );

    HttpContext.Session.Clear();

    return RedirectToAction("Login", "Account");
}

    }

    public class DutyLoginModel
    {
        public string HospitalName { get; set; } = null!;
        public string StaffName { get; set; } = null!;
        public string VehicleNo { get; set; } = null!;
    }
}
