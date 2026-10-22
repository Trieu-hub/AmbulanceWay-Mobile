using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
 
namespace AmbulanceWay.Models
{
    /// <summary>
    /// Bảng lưu tín hiệu từ tài xế phát đến bệnh viện để chuẩn bị tiếp nhận ca.
    /// Luồng: Tài xế đón BN xong → POST /api/HospitalNotification → BV nhận popup → Xác nhận/Từ chối
    /// </summary>
    public class HospitalNotification
    {
        [Key]
        public int Id { get; set; }
 
        // --- Liên kết ca bệnh ---
        public int EmergencyCaseId { get; set; }
        public EmergencyCase EmergencyCase { get; set; } = null!;
 
        // --- Liên kết bệnh viện nhận tín hiệu ---
        public int HospitalId { get; set; }
        public Hospital Hospital { get; set; } = null!;
 
        // --- Thông tin tài xế phát tín hiệu ---
        [Required]
        [MaxLength(100)]
        public string DriverName { get; set; } = null!;
 
        [Required]
        [MaxLength(20)]
        public string VehicleNo { get; set; } = null!;
 
        /// <summary>Thời gian dự kiến đến BV (phút)</summary>
        public int EtaMinutes { get; set; }
 
        /// <summary>Vị trí xe lúc phát tín hiệu</summary>
        [Column(TypeName = "decimal(10,7)")]
        public decimal DriverLat { get; set; }
 
        [Column(TypeName = "decimal(10,7)")]
        public decimal DriverLng { get; set; }
 
        // --- Trạng thái xử lý ---
        /// <summary>PENDING / CONFIRMED / REJECTED</summary>
        [MaxLength(20)]
        public string Status { get; set; } = "PENDING";
 
        /// <summary>Lý do từ chối (nếu REJECTED)</summary>
        [MaxLength(300)]
        public string? RejectReason { get; set; }
 
        /// <summary>Phòng chuẩn bị (BV điền khi confirm)</summary>
        [MaxLength(100)]
        public string? AssignedRoom { get; set; }
 
        public DateTime CreatedAt { get; set; } = DateTime.Now;
        public DateTime? RespondedAt { get; set; }
    }
}
 