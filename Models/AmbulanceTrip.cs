using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace AmbulanceWay.Models
{
    public class AmbulanceTrip
    {
        public int Id { get; set; }

        [Required]
        public string StaffName { get; set; } = null!;

        [Required]
        public string Hospital { get; set; } = null!;

        [Required]
        public string VehicleNo { get; set; } = null!;

        public DateTime ShiftStart { get; set; }
        public DateTime? ShiftEnd { get; set; }

        [Required]
        public string IncidentAddress { get; set; } = null!;

        [Column(TypeName = "decimal(10,7)")]
        public decimal IncidentLat { get; set; }

        [Column(TypeName = "decimal(10,7)")]
        public decimal IncidentLng { get; set; }

        [Required]
        public string HospitalAddress { get; set; } = null!;

        [Column(TypeName = "decimal(10,7)")]
        public decimal HospitalLat { get; set; }

        [Column(TypeName = "decimal(10,7)")]
        public decimal HospitalLng { get; set; }

        [Column(TypeName = "decimal(10,3)")]
        public decimal DistanceKm { get; set; }

        public int EstimatedMinutes { get; set; }

        public string Status { get; set; } = "PENDING";

        public DateTime CreatedAt { get; set; } = DateTime.Now;
    }
}