using Microsoft.AspNetCore.Mvc;
using Microsoft.IdentityModel.Tokens;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using BCrypt.Net;
using AmbulanceWay.Constants;
using AmbulanceWay.Data; // Thay bằng namespace chuẩn của bạn
using AmbulanceWay.Models;

namespace AmbulanceWay.Controllers.Api
{
    [ApiController]
    [Route("api/[controller]")]
    public class AuthController : ControllerBase
    {
        private readonly AmbulanceWayDbContext _context;
        private readonly IConfiguration _configuration;

        public AuthController(AmbulanceWayDbContext context, IConfiguration configuration)
        {
            _context = context;
            _configuration = configuration;
        }

        [HttpPost("login")]
        public IActionResult Login([FromBody] LoginRequest model)
        {
            // Chuẩn hóa giống đăng nhập web (AccountController): bỏ khoảng trắng, không phân biệt hoa thường
            var username = (model.Username ?? "").Trim();
            var password = (model.Password ?? "").Trim();

            // 1. Kiểm tra User thực tế trong Database và xác thực mật khẩu
            var user = _context.Users
                .OrderBy(u => u.Id)
                .FirstOrDefault(u => u.Username.ToLower() == username.ToLower());

            if (user != null && VerifyPassword(password, user.Password))
            {
                // Tài khoản bị khóa không được cấp token (web cũng chặn ở bước này)
                if (user.Status != AppConstants.StatusActive)
                    return StatusCode(StatusCodes.Status403Forbidden, new { Success = false, Message = "Tài khoản đang bị khóa!" });

                // 2. Tạo danh sách Claims dựa trên thông tin User trong DB
                var claims = new[] {
                    new Claim(ClaimTypes.Name, user.Username ?? "Unknown"),
                    new Claim(ClaimTypes.Role, user.Role ?? "DRIVER"),
                    new Claim("UserId", user.Id.ToString() ?? "0"),
                    new Claim("Status", user.Status ?? "ACTIVE")
                };

                // 3. Lấy Key và cấu hình từ appsettings.json
                var jwtKey = _configuration["Jwt:Key"] ?? "Default_Secret_Key_At_Least_32_Chars_Long";
                var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtKey));
                var creds = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);

                // 4. Khởi tạo Token
                var token = new JwtSecurityToken(
                    issuer: _configuration["Jwt:Issuer"],
                    audience: _configuration["Jwt:Audience"],
                    claims: claims,
                    expires: DateTime.UtcNow.AddDays(7),
                    signingCredentials: creds
                );

                // 5. Trả về kết quả cho Mobile
                return Ok(new {
                    Success = true,
                    Token = new JwtSecurityTokenHandler().WriteToken(token),
                    Expiration = token.ValidTo,
                    User = new {
                        user.Username,
                        user.Role
                    }
                });
            }

            return Unauthorized(new { Success = false, Message = "Tài khoản hoặc mật khẩu không đúng." });
        }

        // Cùng quy tắc với AccountController.Login: mật khẩu chưa hash (seed tay bằng SQL) thì so sánh trực tiếp
        private static bool VerifyPassword(string password, string storedPassword)
        {
            try
            {
                return BCrypt.Net.BCrypt.Verify(password, storedPassword);
            }
            catch
            {
                return storedPassword == password;
            }
        }
    }

    // Class nhận dữ liệu từ Request
    public class LoginRequest
    {
        public string Username { get; set; } = null!;
        public string Password { get; set; } = null!;
    }
}