using System.ComponentModel.DataAnnotations;

namespace AmbulanceWay.Models
{
    public class TripAttachment
    {
        public int Id { get; set; }

        public int TripId { get; set; }

        [Required]
        public string Url { get; set; } = null!; // Azure Blob / S3 URL

        [Required]
        [MaxLength(50)]
        public string Type { get; set; } = null!; // "arrival", "patient_loaded", "delivered", "vehicle_after"

        public string? Description { get; set; }

        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        // Navigation
        public AmbulanceTrip Trip { get; set; } = null!;
    }
}
