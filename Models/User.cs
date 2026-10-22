using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace AmbulanceWay.Models
{
    [Table("Users")]
    public class User
    {
        [Key]
        public int Id { get; set; }

        [Required]
        [StringLength(50)]
        public string Username { get; set; } = string.Empty;

        // Chỉ nên giữ 1 cái để tránh bối rối khi code Controller
        [Required]
        [StringLength(255)]
        [Column("Password")] // Chỉ định rõ tên cột trong SQL là Password
        public string Password { get; set; } = string.Empty;

        [StringLength(20)]
        public string Role { get; set; } = "STAFF";

        [StringLength(20)]
        public string Status { get; set; } = "ACTIVE";

        public bool IsOnline { get; set; } = false;

        public DateTime CreatedAt { get; set; } = DateTime.Now;
    }
}