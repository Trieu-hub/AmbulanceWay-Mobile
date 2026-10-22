using System.ComponentModel.DataAnnotations;

namespace AmbulanceWay.Models
{
    public class OtpVerification
    {
        [Key]
        public int Id { get; set; }

        [Required]
        [MaxLength(20)]
        public string PhoneNumber { get; set; } = null!;

        [Required]
        [MaxLength(10)]
        public string OtpCode { get; set; } = null!;

        public DateTime ExpiresAt { get; set; }

        public DateTime? UsedAt { get; set; }

        public int Attempts { get; set; } = 0;

        [MaxLength(50)]
        public string? Purpose { get; set; } = "REGISTER";

        public DateTime CreatedAt { get; set; } = DateTime.Now;
    }
}

