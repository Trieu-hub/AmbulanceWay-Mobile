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

        public DbSet<AmbulanceTrip> AmbulanceTrips { get; set; } = null!;
        public DbSet<User> Users { get; set; } = null!;
        public DbSet<Driver> Drivers { get; set; } = null!;
        public DbSet<Hospital> Hospitals { get; set; } = null!;

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            // --- Cấu hình cho table USERS (Khắc phục lỗi Invalid Column Name) ---
            modelBuilder.Entity<User>(entity =>
            {
                entity.ToTable("Users"); // Khớp với tên bảng SQL
                entity.HasKey(e => e.Id);

                entity.Property(e => e.Username)
                      .IsRequired()
                      .HasMaxLength(50);

                // Ánh xạ thuộc tính PasswordHash trong code vào cột Password trong SQL
                entity.Property(e => e.PasswordHash)
                      .HasColumnName("Password") 
                      .IsRequired()
                      .HasMaxLength(255);

                entity.Property(e => e.Role)
                      .HasDefaultValue("STAFF")
                      .HasMaxLength(20);

                entity.Property(e => e.Status)
                      .HasDefaultValue("ACTIVE")
                      .HasMaxLength(20);

                entity.Property(e => e.IsOnline)
                      .HasDefaultValue(false);

                // Khớp với cột CreatedAt DATETIME2 trong SQL
                entity.Property(e => e.CreatedAt)
                      .HasColumnName("CreatedAt")
                      .HasDefaultValueSql("SYSDATETIME()"); 
            });

            // --- Cấu hình cho table AmbulanceTrips ---
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

                entity.Property(e => e.Status)
                      .HasMaxLength(50)
                      .HasDefaultValue("PENDING");

                entity.Property(e => e.CreatedAt)
                      .HasDefaultValueSql("GETDATE()");
            });
        }
    }
}