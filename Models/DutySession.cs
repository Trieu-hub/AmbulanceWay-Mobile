using System.ComponentModel.DataAnnotations;

namespace AmbulanceWay.Models
{
    public class DutySession
    {
        [Key]
        public int Id { get; set; }

        [Required]
        [MaxLength(200)]
        public string HospitalName { get; set; } = null!; // Trạm trực

        [Required]
        [MaxLength(100)]
        public string StaffName { get; set; } = null!; // Tên tài xế

        [Required]
        [MaxLength(20)]
        public string VehicleNo { get; set; } = null!; // Biển số xe (Thêm mới)

        [Required]
        public string Username { get; set; } = null!; // Để biết tài khoản nào đang trực

        public DateTime StartTime { get; set; } = DateTime.Now;
        
        public DateTime? EndTime { get; set; } // Để sau này làm chức năng "Kết thúc ca"
    }
}