using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Microsoft.IdentityModel.Tokens;

namespace AmbulanceWay.Controllers.Api
{
    /// <summary>
    /// Tạo JWT cho app mobile, dùng chung cấu hình Jwt:* với AuthController
    /// để middleware JwtBearer trong Program.cs xác thực được.
    /// </summary>
    public static class MobileJwt
    {
        public const string PatientProfileIdClaim = "PatientProfileId";

        public static string Create(IConfiguration configuration, IEnumerable<Claim> claims, TimeSpan lifetime)
        {
            var jwtKey = configuration["Jwt:Key"] ?? "Default_Secret_Key_At_Least_32_Chars_Long";
            var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtKey));
            var creds = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);

            var token = new JwtSecurityToken(
                issuer: configuration["Jwt:Issuer"],
                audience: configuration["Jwt:Audience"],
                claims: claims,
                expires: DateTime.UtcNow.Add(lifetime),
                signingCredentials: creds
            );

            return new JwtSecurityTokenHandler().WriteToken(token);
        }

        /// <summary>Lấy Id hồ sơ bệnh nhân từ token (null nếu token không phải của bệnh nhân).</summary>
        public static int? GetPatientProfileId(ClaimsPrincipal user)
        {
            var raw = user.FindFirst(PatientProfileIdClaim)?.Value;
            return int.TryParse(raw, out var id) ? id : null;
        }
    }
}
