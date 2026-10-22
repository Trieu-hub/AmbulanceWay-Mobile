using Microsoft.AspNetCore.Mvc;
using AmbulanceWay.Constants;

namespace AmbulanceWay.Controllers
{
    [Route("HospitalPortal")]
    public class HospitalPortalMvcController : Controller
    {
        [HttpGet("Dashboard")]
        public IActionResult Dashboard()
        {
            var role = HttpContext.Session.GetInt32(AppConstants.SessionRole);
            if (role != AppConstants.RoleValueHospital)
            {
                return RedirectToAction("Login", "Account");
            }
            // View nằm ở Views/HospitalPortal (tên controller là HospitalPortalMvc nên phải chỉ rõ đường dẫn)
            return View("~/Views/HospitalPortal/Dashboard.cshtml");
        }
    }
}
