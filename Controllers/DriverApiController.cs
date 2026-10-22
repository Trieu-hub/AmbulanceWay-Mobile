using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using System.Security.Claims;

namespace AmbulanceWay.Controllers.Api
{
    [Authorize] // Chỉ những request có Token mới vào được đây
    [ApiController]
    [Route("api/[controller]")]
    public class DriverApiController : ControllerBase
    {
        // GET /api/DriverApi/me
        [HttpGet("me")]
        public IActionResult GetProfile()
        {
            // Lấy thông tin từ Claims trong Token
            var username = User.Identity?.Name;
            var role = User.FindFirst(ClaimTypes.Role)?.Value;
            var userId = User.FindFirst("UserId")?.Value;

            return Ok(new {
                Message = "Xác thực thành công",
                Data = new {
                    Username = username,
                    Role = role,
                    UserId = userId
                }
            });
        }

        // POST /api/DriverApi/duty/start
        [HttpPost("duty/start")]
        public IActionResult StartDuty([FromBody] DutyRequest model)
        {
            // Ở đây bạn sẽ viết logic lưu ca trực vào Database
            // Ví dụ: _context.Duties.Add(new Duty { ... });
            
            return Ok(new { 
                Success = true, 
                Message = $"Tài xế {model.staffName} đã bắt đầu ca trên xe {model.vehicleNo}" 
            });
        }
    }

    public class DutyRequest 
    {
        public string hospitalName { get; set; } = null!;
        public string staffName { get; set; } = null!;
        public string vehicleNo { get; set; } = null!;
    }
}