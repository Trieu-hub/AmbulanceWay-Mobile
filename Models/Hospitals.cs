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
 
        // ===== THÊM MỚI: Quản lý công suất tiếp nhận =====
 
        /// <summary>Tổng số giường cấp cứu</summary>
        public int TotalEmergencyBeds { get; set; } = 0;
 
        /// <summary>Số giường trống hiện tại (cập nhật realtime bởi BV)</summary>
        public int AvailableEmergencyBeds { get; set; } = 0;
 
        /// <summary>Trạng thái tiếp nhận: OPEN / FULL / CLOSED</summary>
        [MaxLength(20)]
        public string ReceptionStatus { get; set; } = "OPEN";
 
        /// <summary>Thời điểm cập nhật trạng thái gần nhất</summary>
        public DateTime? StatusUpdatedAt { get; set; }
 
        /// <summary>Ghi chú nhanh từ BV (VD: "Không có BS tim mạch trực")</summary>
        [MaxLength(300)]
        public string? StatusNote { get; set; }
 
        // Navigation
        public ICollection<HospitalNotification> Notifications { get; set; } = new List<HospitalNotification>();
    }
}
 