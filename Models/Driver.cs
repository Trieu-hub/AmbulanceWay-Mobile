namespace AmbulanceWay.Models
{
    public class Driver
    {
        public int Id { get; set; }

        public int UserId { get; set; }

         public string DriverName { get; set; } = null!;

        public string Station { get; set; } = null!;

        public string Vehicle { get; set; } = null!;

        public string Phone { get; set; } = null!;

        public User User { get; set; } = null!;
    }
}