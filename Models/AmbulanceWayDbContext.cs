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

        public DbSet<AmbulanceTrip> AmbulanceTrips { get; set; }
        public DbSet<User> Users { get; set; }
        public DbSet<Driver> Drivers { get; set; }
        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<AmbulanceTrip>(entity =>
            {
                entity.HasKey(e => e.Id);

                entity.Property(e => e.DistanceKm)
                      .HasColumnType("decimal(10,2)");

                entity.Property(e => e.HospitalLat)
                      .HasColumnType("decimal(9,6)");

                entity.Property(e => e.HospitalLng)
                      .HasColumnType("decimal(9,6)");

                entity.Property(e => e.IncidentLat)
                      .HasColumnType("decimal(9,6)");

                entity.Property(e => e.IncidentLng)
                      .HasColumnType("decimal(9,6)");

                entity.Property(e => e.StaffName)
                      .IsRequired()
                      .HasMaxLength(100);

                entity.Property(e => e.Hospital)
                      .IsRequired()
                      .HasMaxLength(200);

                entity.Property(e => e.VehicleNo)
                      .IsRequired()
                      .HasMaxLength(50);

                entity.Property(e => e.IncidentAddress)
                      .IsRequired()
                      .HasMaxLength(300);

                entity.Property(e => e.HospitalAddress)
                      .IsRequired()
                      .HasMaxLength(300);

                entity.Property(e => e.CreatedAt)
                      .HasDefaultValueSql("GETDATE()");
            });
        }
    }
}