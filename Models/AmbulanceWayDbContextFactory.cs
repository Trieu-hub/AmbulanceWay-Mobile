using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;
using Microsoft.Extensions.Configuration;
using System.IO;

namespace AmbulanceWay.Data
{
    public class AmbulanceWayDbContextFactory
        : IDesignTimeDbContextFactory<AmbulanceWayDbContext>
    {
        public AmbulanceWayDbContext CreateDbContext(string[] args)
        {
            var basePath = Directory.GetCurrentDirectory();

            var configuration = new ConfigurationBuilder()
                .SetBasePath(basePath)
                .AddJsonFile("appsettings.json", optional: false)
                .Build();

            var optionsBuilder = new DbContextOptionsBuilder<AmbulanceWayDbContext>();

            var connectionString = configuration.GetConnectionString("DefaultConnection");

            optionsBuilder.UseSqlServer(connectionString);

            return new AmbulanceWayDbContext(optionsBuilder.Options);
        }
    }
}