using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace AmbulanceWay.Models
{
    [Table("Users")] // Đảm bảo EF Core tìm đúng bảng Users
    public class User
    {
        [Key]
        public int Id { get; set; }

        [Required]
        [StringLength(50)]
        public string Username { get; set; } = string.Empty;

        [Required]
        [StringLength(255)]
        public string Password { get; set; } = string.Empty;

        // Lưu ý: Trong SQL bạn để Password, nhưng trong Controller bạn dùng PasswordHash.
        // Nếu dùng PasswordHash trong code thì đổi tên cột này lại cho khớp hoặc dùng [Column("Password")]
        [Column("Password")]
        public string PasswordHash { get; set; } = string.Empty;

        [StringLength(20)]
        public string Role { get; set; } = "STAFF";

        [StringLength(20)]
        public string Status { get; set; } = "ACTIVE";

        public bool IsOnline { get; set; } = false;

        public DateTime CreatedAt { get; set; } = DateTime.Now;
    }
}