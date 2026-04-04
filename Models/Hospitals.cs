using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace AmbulanceWay.Models
{
    public class Hospital
    {
        public int Id { get; set; }

        [Required]
        [MaxLength(200)]
        public string Name { get; set; } = null!;

        [Required]
        [MaxLength(300)]
        public string Address { get; set; } = null!;

        [Column(TypeName = "decimal(10,7)")]
        public decimal Lat { get; set; }

        [Column(TypeName = "decimal(10,7)")]
        public decimal Lng { get; set; }

        [MaxLength(20)]
        public string? Phone { get; set; }

        [MaxLength(100)]
        public string? Type { get; set; } 
        public bool IsActive { get; set; } = true;
    }
}