using System.ComponentModel.DataAnnotations;
 
namespace AmbulanceWay.Models
{
    /// <summary>
    /// Tài khoản đăng nhập dành riêng cho nhân viên bệnh viện.
    /// Tách biệt với bảng Users (tài xế/admin) để quản lý độc lập.
    /// </summary>
    public class HospitalUser
    {
        [Key]
        public int Id { get; set; }
 
        public int HospitalId { get; set; }
        public Hospital Hospital { get; set; } = null!;
 
        [Required]
        [MaxLength(50)]
        public string Username { get; set; } = null!;
 
        [Required]
        [MaxLength(255)]
        public string Password { get; set; } = null!;
 
        [Required]
        [MaxLength(100)]
        public string FullName { get; set; } = null!;
 
        [MaxLength(20)]
        public string? Phone { get; set; }
 
        /// <summary>ACTIVE / INACTIVE</summary>
        [MaxLength(20)]
        public string Status { get; set; } = "ACTIVE";
 
        public DateTime CreatedAt { get; set; } = DateTime.Now;
    }
}