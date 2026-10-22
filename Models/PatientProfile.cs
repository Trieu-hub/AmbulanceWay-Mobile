using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace AmbulanceWay.Models
{
    public class PatientProfile
    {
        [Key]
        public int Id { get; set; }

        [Required]
        [MaxLength(100)]
        public string FullName { get; set; } = null!;

        [Required]
        [MaxLength(20)]
        public string PhoneNumber { get; set; } = null!;

        [Required]
        public DateTime BirthDate { get; set; }

        [Required]
        [MaxLength(10)]
        public string Gender { get; set; } = null!; // Nam/Nữ/Khác

        [Required]
        [MaxLength(300)]
        public string PermanentAddress { get; set; } = null!;

        [MaxLength(500)]
        public string? MedicalHistory { get; set; }

        [MaxLength(500)]
        public string? DrugAllergies { get; set; }

        [Required]
        [MaxLength(100)]
        public string EmergencyContactName { get; set; } = null!;

        [Required]
        [MaxLength(20)]
        public string EmergencyContactPhone { get; set; } = null!;

        public bool IsOtpVerified { get; set; } = false;

        public DateTime CreatedAt { get; set; } = DateTime.Now;
        public DateTime UpdatedAt { get; set; } = DateTime.Now;
    }
}

