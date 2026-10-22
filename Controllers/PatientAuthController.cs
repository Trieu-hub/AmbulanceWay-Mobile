using AmbulanceWay.Constants;
using AmbulanceWay.Controllers.Api;
using AmbulanceWay.Data;
using AmbulanceWay.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;
using System.Security.Claims;
using System.Security.Cryptography;

namespace AmbulanceWay.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class PatientAuthController : ControllerBase
    {
        private readonly AmbulanceWayDbContext _context;
        private readonly IConfiguration _configuration;

        private const string OtpPurposeRegister = "REGISTER";
        private const string OtpPurposeLogin = "LOGIN";
        private const int OtpMaxAttempts = 5;

        public PatientAuthController(AmbulanceWayDbContext context, IConfiguration configuration)
        {
            _context = context;
            _configuration = configuration;
        }

        private static string GenerateOtp()
            => RandomNumberGenerator.GetInt32(100000, 1000000).ToString();

        // POST api/patientauth/register
        // Web: Patient đăng ký profile -> hệ thống tạo OTP lưu vào DB
        [HttpPost("register")]
        public async Task<IActionResult> Register([FromBody] PatientRegisterRequest req)
        {
            if (req == null) return BadRequest(new { message = "Dữ liệu trống" });
            if (string.IsNullOrWhiteSpace(req.PhoneNumber)) return BadRequest(new { message = "Thiếu SĐT" });
            if (string.IsNullOrWhiteSpace(req.FullName)) return BadRequest(new { message = "Thiếu họ tên" });

            var now = DateTime.UtcNow;
            var otpCode = GenerateOtp();
            var expireAt = now.AddMinutes(5);

            var profile = await _context.PatientProfiles
                .FirstOrDefaultAsync(p => p.PhoneNumber == req.PhoneNumber);

            if (profile == null)
            {
                profile = new PatientProfile
                {
                    FullName = req.FullName!,
                    PhoneNumber = req.PhoneNumber!,
                    BirthDate = req.BirthDate!.Value,
                    Gender = req.Gender!,
                    PermanentAddress = req.PermanentAddress!,
                    MedicalHistory = req.MedicalHistory,
                    DrugAllergies = req.DrugAllergies,
                    EmergencyContactName = req.EmergencyContactName!,
                    EmergencyContactPhone = req.EmergencyContactPhone!,
                    IsOtpVerified = false,
                    CreatedAt = DateTime.UtcNow,
                    UpdatedAt = DateTime.UtcNow
                };

                _context.PatientProfiles.Add(profile);
            }
            else
            {
                // cập nhật thông tin profile
                profile.FullName = req.FullName!;
                profile.BirthDate = req.BirthDate!.Value;
                profile.Gender = req.Gender!;
                profile.PermanentAddress = req.PermanentAddress!;
                profile.MedicalHistory = req.MedicalHistory;
                profile.DrugAllergies = req.DrugAllergies;
                profile.EmergencyContactName = req.EmergencyContactName!;
                profile.EmergencyContactPhone = req.EmergencyContactPhone!;
                profile.IsOtpVerified = false;
                profile.UpdatedAt = DateTime.UtcNow;
            }

            // tạo OTP mới (V1: tạo bản ghi mới, không xoá cũ)
            var otp = new OtpVerification
            {
                PhoneNumber = req.PhoneNumber!,
                OtpCode = otpCode,
                ExpiresAt = expireAt,
                Attempts = 0,
                Purpose = OtpPurposeRegister,
                CreatedAt = now
            };
            _context.OtpVerifications.Add(otp);

            await _context.SaveChangesAsync();

            // TODO: tích hợp SMS/OTP provider.
            // V1: trả OTP để test nhanh.
            return Ok(new { success = true, otp = otpCode, expiresInSeconds = 5 * 60 });
        }

        // POST api/patientauth/login
        // Mobile: bệnh nhân đã có hồ sơ đăng nhập lại bằng SĐT -> tạo OTP mới, xác thực qua verify-otp
        [HttpPost("login")]
        public async Task<IActionResult> Login([FromBody] PatientLoginRequest req)
        {
            if (req == null || string.IsNullOrWhiteSpace(req.PhoneNumber))
                return BadRequest(new { success = false, message = "Thiếu SĐT" });

            var phone = req.PhoneNumber.Trim();

            var exists = await _context.PatientProfiles.AnyAsync(p => p.PhoneNumber == phone);
            if (!exists)
                return NotFound(new { success = false, message = "Số điện thoại này chưa đăng ký hồ sơ" });

            var now = DateTime.UtcNow;
            var otpCode = GenerateOtp();

            _context.OtpVerifications.Add(new OtpVerification
            {
                PhoneNumber = phone,
                OtpCode = otpCode,
                ExpiresAt = now.AddMinutes(5),
                Attempts = 0,
                Purpose = OtpPurposeLogin,
                CreatedAt = now
            });
            await _context.SaveChangesAsync();

            // TODO: tích hợp SMS/OTP provider.
            // V1: trả OTP để test nhanh (giống register).
            return Ok(new { success = true, otp = otpCode, expiresInSeconds = 5 * 60 });
        }

        // POST api/patientauth/verify-otp
        [HttpPost("verify-otp")]
        public async Task<IActionResult> VerifyOtp([FromBody] VerifyOtpRequest req)
        {
            if (req == null) return BadRequest(new { message = "Dữ liệu trống" });
            if (string.IsNullOrWhiteSpace(req.PhoneNumber) || string.IsNullOrWhiteSpace(req.OtpCode))
                return BadRequest(new { message = "Thiếu SĐT hoặc OTP" });

            var now = DateTime.UtcNow;

            var otp = await _context.OtpVerifications
                .OrderByDescending(x => x.Id)
                .FirstOrDefaultAsync(x => x.PhoneNumber == req.PhoneNumber
                                       && (x.Purpose == OtpPurposeRegister || x.Purpose == OtpPurposeLogin));

            if (otp == null) return BadRequest(new { success = false, message = "OTP không tồn tại" });
            // Mỗi OTP chỉ dùng được 1 lần vì xác thực thành công sẽ cấp token đăng nhập
            if (otp.UsedAt != null) return BadRequest(new { success = false, message = "OTP đã được sử dụng, vui lòng lấy mã mới" });
            if (otp.ExpiresAt < now) return BadRequest(new { success = false, message = "OTP đã hết hạn" });
            if (otp.Attempts >= OtpMaxAttempts) return BadRequest(new { success = false, message = "Nhập sai quá nhiều lần, vui lòng lấy mã mới" });
            if (!string.Equals(otp.OtpCode, req.OtpCode, StringComparison.Ordinal))
            {
                otp.Attempts += 1;
                await _context.SaveChangesAsync();
                return BadRequest(new { success = false, message = "OTP sai" });
            }

            otp.UsedAt = now;

            var profile = await _context.PatientProfiles
                .FirstOrDefaultAsync(p => p.PhoneNumber == req.PhoneNumber);

            if (profile == null)
                return BadRequest(new { success = false, message = "Không tìm thấy profile" });

            profile.IsOtpVerified = true;
            profile.UpdatedAt = DateTime.UtcNow;

            await _context.SaveChangesAsync();

            // Token cho app mobile gọi các API /api/mobile/patient/* (web không dùng tới các field này)
            var token = MobileJwt.Create(_configuration, new[]
            {
                new Claim(ClaimTypes.Name, profile.PhoneNumber),
                new Claim(ClaimTypes.Role, AppConstants.RolePatient),
                new Claim(MobileJwt.PatientProfileIdClaim, profile.Id.ToString())
            }, TimeSpan.FromDays(7));

            return Ok(new
            {
                success = true,
                verified = true,
                profileId = profile.Id,
                fullName = profile.FullName,
                token
            });
        }

        public class PatientLoginRequest
        {
            public string? PhoneNumber { get; set; }
        }

        public class PatientRegisterRequest
        {
            public string? FullName { get; set; }
            public string? PhoneNumber { get; set; }
            public DateTime? BirthDate { get; set; }
            public string? Gender { get; set; }
            public string? PermanentAddress { get; set; }
            public string? MedicalHistory { get; set; }
            public string? DrugAllergies { get; set; }
            public string? EmergencyContactName { get; set; }
            public string? EmergencyContactPhone { get; set; }
        }

        public class VerifyOtpRequest
        {
            public string? PhoneNumber { get; set; }
            public string? OtpCode { get; set; }
        }
    }
}
