using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace AmbulanceWay.Models
{
    public class TripHistory
    {
        [Key]
        public int Id { get; set; }

        [Required]
        [MaxLength(100)]
        public string DriverName { get; set; } = null!;

        [Required]
        [MaxLength(20)]
        public string VehicleNo { get; set; } = null!;

        [Required]
        [MaxLength(200)]
        public string HospitalName { get; set; } = null!;

        [MaxLength(300)]
        public string? HospitalAddress { get; set; }

        [Column(TypeName = "decimal(10,7)")]
        public decimal HospitalLat { get; set; }

        [Column(TypeName = "decimal(10,7)")]
        public decimal HospitalLng { get; set; }

        [Required]
        [MaxLength(300)]
        public string PatientAddress { get; set; } = null!;

        [Column(TypeName = "decimal(10,7)")]
        public decimal PatientLat { get; set; }

        [Column(TypeName = "decimal(10,7)")]
        public decimal PatientLng { get; set; }

        [Column(TypeName = "decimal(10,3)")]
        public decimal DistanceKm { get; set; }

        public int DurationMinutes { get; set; }

        [MaxLength(50)]
        public string TripStatus { get; set; } = "COMPLETED"; // PENDING, ACCEPTED, COMPLETED, CANCELLED

        public DateTime CreatedAt { get; set; } = DateTime.Now;

        public DateTime? CompletedAt { get; set; }

        // --- Rating sau chuyến ---
        [Range(1, 5)]
        public int? OverallRating { get; set; } // 1-5

        [Range(1, 5)]
        public int? TimeRating { get; set; }

        [Range(1, 5)]
        public int? AttitudeRating { get; set; }

        [Range(1, 5)]
        public int? VehicleRating { get; set; }

        [Range(1, 5)]
        public int? SituationRating { get; set; }

        [MaxLength(1000)]
        public string? DriverNote { get; set; }

        public int? EmergencyCaseId { get; set; }
    }
}


