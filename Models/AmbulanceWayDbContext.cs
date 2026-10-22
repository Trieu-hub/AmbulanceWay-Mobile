using Microsoft.EntityFrameworkCore;
using AmbulanceWay.Models;
 
namespace AmbulanceWay.Data
{
    public class AmbulanceWayDbContext : DbContext
    {
        public AmbulanceWayDbContext(DbContextOptions<AmbulanceWayDbContext> options)
            : base(options)
        {
        }
 
        // --- Bảng cũ (giữ nguyên) ---
        public DbSet<AmbulanceTrip> AmbulanceTrips { get; set; } = null!;
        public DbSet<User> Users { get; set; } = null!;
        public DbSet<Driver> Drivers { get; set; } = null!;
        public DbSet<Hospital> Hospitals { get; set; } = null!;
        public DbSet<DutySession> DutySessions { get; set; } = null!;
        public DbSet<TripAttachment> TripAttachments { get; set; } = null!;
        public DbSet<TripHistory> TripHistories { get; set; } = null!;
        public DbSet<PatientProfile> PatientProfiles { get; set; } = null!;
        public DbSet<OtpVerification> OtpVerifications { get; set; } = null!;
        public DbSet<EmergencyCase> EmergencyCases { get; set; } = null!;
 
        // --- Bảng mới ---
        public DbSet<HospitalNotification> HospitalNotifications { get; set; } = null!;
        public DbSet<PatientRating> PatientRatings { get; set; } = null!;
        public DbSet<HospitalUser> HospitalUsers { get; set; } = null!;
 
        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            // --- Users ---
            modelBuilder.Entity<User>(entity =>
            {
                entity.ToTable("Users");
                entity.HasKey(e => e.Id);
                entity.Property(e => e.Username).IsRequired().HasMaxLength(50);
                entity.Property(e => e.Password).HasColumnName("Password").IsRequired().HasMaxLength(255);
                entity.Property(e => e.Role).HasDefaultValue("STAFF").HasMaxLength(20);
                entity.Property(e => e.Status).HasDefaultValue("ACTIVE").HasMaxLength(20);
                entity.Property(e => e.IsOnline).HasDefaultValue(false);
                entity.Property(e => e.CreatedAt).HasColumnName("CreatedAt").HasDefaultValueSql("SYSDATETIME()");
            });
 
            // --- AmbulanceTrips ---
            modelBuilder.Entity<AmbulanceTrip>(entity =>
            {
                entity.HasKey(e => e.Id);
                entity.Property(e => e.DistanceKm).HasColumnType("decimal(10,3)");
                entity.Property(e => e.HospitalLat).HasColumnType("decimal(10,7)");
                entity.Property(e => e.HospitalLng).HasColumnType("decimal(10,7)");
                entity.Property(e => e.IncidentLat).HasColumnType("decimal(10,7)");
                entity.Property(e => e.IncidentLng).HasColumnType("decimal(10,7)");
                entity.Property(e => e.StaffName).IsRequired().HasMaxLength(100);
                entity.Property(e => e.Hospital).IsRequired().HasMaxLength(200);
                entity.Property(e => e.VehicleNo).IsRequired().HasMaxLength(50);
                entity.Property(e => e.IncidentAddress).IsRequired().HasMaxLength(300);
                entity.Property(e => e.HospitalAddress).IsRequired().HasMaxLength(300);
                entity.Property(e => e.Status).HasMaxLength(50).HasDefaultValue("PENDING");
                entity.Property(e => e.CreatedAt).HasDefaultValueSql("GETDATE()");
            });
 
            // --- EmergencyCase ---
            modelBuilder.Entity<EmergencyCase>(entity =>
            {
                entity.HasKey(e => e.Id);
                entity.Property(e => e.PatientLat).HasColumnType("decimal(10,7)");
                entity.Property(e => e.PatientLng).HasColumnType("decimal(10,7)");
                entity.HasOne(e => e.PatientProfile)
                      .WithMany()
                      .HasForeignKey(e => e.PatientProfileId)
                      .OnDelete(DeleteBehavior.Restrict);

                entity.HasOne(e => e.Driver)
                      .WithMany()
                      .HasForeignKey(e => e.DriverId)
                      .OnDelete(DeleteBehavior.SetNull);

                entity.HasMany(e => e.HospitalNotifications)
                      .WithOne(n => n.EmergencyCase)
                      .HasForeignKey(n => n.EmergencyCaseId)
                      .OnDelete(DeleteBehavior.Cascade);
            });
 
            // --- HospitalNotification ---
            modelBuilder.Entity<HospitalNotification>(entity =>
            {
                entity.HasKey(e => e.Id);
                entity.Property(e => e.DriverLat).HasColumnType("decimal(10,7)");
                entity.Property(e => e.DriverLng).HasColumnType("decimal(10,7)");
                entity.HasOne(e => e.Hospital)
                      .WithMany(h => h.Notifications)
                      .HasForeignKey(e => e.HospitalId)
                      .OnDelete(DeleteBehavior.Restrict);
            });
 
            // --- PatientRating ---
            modelBuilder.Entity<PatientRating>(entity =>
            {
                entity.HasKey(e => e.Id);
                entity.HasOne(e => e.EmergencyCase)
                      .WithMany()
                      .HasForeignKey(e => e.EmergencyCaseId)
                      .OnDelete(DeleteBehavior.Restrict);
                // Mỗi ca chỉ được đánh giá 1 lần
                entity.HasIndex(e => e.EmergencyCaseId).IsUnique();
            });
 
            // --- HospitalUser ---
            modelBuilder.Entity<HospitalUser>(entity =>
            {
                entity.HasKey(e => e.Id);
                entity.HasOne(e => e.Hospital)
                      .WithMany()
                      .HasForeignKey(e => e.HospitalId)
                      .OnDelete(DeleteBehavior.Cascade);
                entity.HasIndex(e => e.Username).IsUnique();
            });
        }
    }
}