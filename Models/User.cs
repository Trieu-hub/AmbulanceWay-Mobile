namespace AmbulanceWay.Models
{
    public class User
    {
        public int Id { get; set; }
        public string Username { get; set; } = null!;
        public string PasswordHash { get; set; } = null!;
        public int RoleId { get; set; }
        public string Status { get; set; } = "ACTIVE";
        public bool IsOnline { get; set; } = false;
    }
}