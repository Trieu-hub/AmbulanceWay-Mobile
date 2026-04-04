using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace AmbulanceWay.Models
{
    public class Driver
    {
        public int Id { get; set; }

        public int UserId { get; set; }

        [Required]
        [MaxLength(100)]
        public string DriverName { get; set; } = null!;

        [Required]
        [MaxLength(200)]
        public string Station { get; set; } = null!;

        [Required]
        [MaxLength(50)]
        public string Vehicle { get; set; } = null!;

        [Required]
        [MaxLength(20)]
        public string Phone { get; set; } = null!;

        [MaxLength(20)]
        public string Status { get; set; } = "ONLINE";

        [ForeignKey("UserId")]
        public User User { get; set; } = null!;
    }
}