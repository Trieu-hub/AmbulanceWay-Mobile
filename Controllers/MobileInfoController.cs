using Microsoft.AspNetCore.Mvc;

namespace AmbulanceWay.Controllers.Api
{
    /// <summary>
    /// Endpoint không cần đăng nhập để app mobile kiểm tra địa chỉ máy chủ đã nhập đúng chưa.
    /// </summary>
    [ApiController]
    [Route("api/mobile")]
    public class MobileInfoController : ControllerBase
    {
        // GET /api/mobile/ping
        [HttpGet("ping")]
        public IActionResult Ping()
        {
            return Ok(new { ok = true, app = "AmbulanceWay", serverTimeUtc = DateTime.UtcNow });
        }
    }
}
