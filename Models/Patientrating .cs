using System.ComponentModel.DataAnnotations;
 
namespace AmbulanceWay.Models
{
    /// <summary>
    /// Đánh giá chất lượng dịch vụ của bệnh nhân sau chuyến đi.
    /// Bệnh nhân được gửi link đánh giá qua SĐT sau khi ca hoàn thành.
    /// </summary>
    public class PatientRating
    {
        [Key]
        public int Id { get; set; }
 
        public int EmergencyCaseId { get; set; }
        public EmergencyCase EmergencyCase { get; set; } = null!;
 
        public int PatientProfileId { get; set; }
 
        // --- Điểm đánh giá (1-5) ---
        [Range(1, 5)]
        public int OverallRating { get; set; }
 
        [Range(1, 5)]
        public int ResponseTimeRating { get; set; }   // Thời gian phản hồi
 
        [Range(1, 5)]
        public int DriverAttitudeRating { get; set; } // Thái độ tài xế
 
        [Range(1, 5)]
        public int VehicleConditionRating { get; set; } // Tình trạng xe
 
        [Range(1, 5)]
        public int SituationHandlingRating { get; set; } // Xử lý tình huống
 
        [MaxLength(1000)]
        public string? Comment { get; set; }
 
        public DateTime CreatedAt { get; set; } = DateTime.Now;
    }
}