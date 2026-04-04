using System.ComponentModel.DataAnnotations;

public class DutySession
{
    [Required]
    [MaxLength(200)]
    public string HospitalName { get; set; } = null!;

    [Required]
    [MaxLength(100)]
    public string StaffName { get; set; } = null!;

    [Required]
    [MaxLength(20)]
    public string Phone { get; set; } = null!;

    public DateTime StartTime { get; set; } = DateTime.Now;
}