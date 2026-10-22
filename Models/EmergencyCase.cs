using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
 
namespace AmbulanceWay.Models
{
    public class EmergencyCase
    {
        [Key]
        public int Id { get; set; }
 
        [Required]
        [MaxLength(30)]
        public string EmergencyType { get; set; } = null!; // tai_nan / tim_mach / dot_quy / sinh_san / khac
 
        [Required]
        [MaxLength(1000)]
        public string Description { get; set; } = null!;
 
        [Required]
        [MaxLength(300)]
        public string PatientAddress { get; set; } = null!;
 
        [Column(TypeName = "decimal(10,7)")]
        public decimal PatientLat { get; set; }
 
        [Column(TypeName = "decimal(10,7)")]
        public decimal PatientLng { get; set; }
 
        [Required]
        public int PatientProfileId { get; set; }
 
        /// <summary>OPEN / ASSIGNED / PICKED_UP / DELIVERING / COMPLETED / CANCELLED</summary>
        [MaxLength(50)]
        public string Status { get; set; } = "OPEN";
 
        // ===== THÊM MỚI: Thông tin tài xế được giao =====

        public int? DriverId { get; set; }

        [ForeignKey("DriverId")]
        public virtual Driver? Driver { get; set; }
 
        /// <summary>Username của tài xế đã nhận cuốc</summary>
        [MaxLength(100)]
        public string? AssignedDriverUsername { get; set; }
 
        [MaxLength(100)]
        public string? AssignedDriverName { get; set; }
 
        [MaxLength(20)]
        public string? AssignedVehicleNo { get; set; }
 
        public DateTime? AcceptedAt { get; set; }
 
        public DateTime? PickedUpAt { get; set; }
 
        public DateTime? CompletedAt { get; set; }
 
        /// <summary>BV đã xác nhận tiếp nhận (từ HospitalNotification)</summary>
        public int? ConfirmedHospitalId { get; set; }
 
        public DateTime CreatedAt { get; set; } = DateTime.Now;
 
        // Navigation
        public PatientProfile? PatientProfile { get; set; }
        public ICollection<HospitalNotification> HospitalNotifications { get; set; } = new List<HospitalNotification>();
    }
}