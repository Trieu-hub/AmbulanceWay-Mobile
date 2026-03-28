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
            var configuration = new ConfigurationBuilder()
                .SetBasePath(Directory.GetCurrentDirectory())
                .AddJsonFile("appsettings.json")
                .Build();

            var optionsBuilder = new DbContextOptionsBuilder<AmbulanceWayDbContext>();
            optionsBuilder.UseSqlServer(
                configuration.GetConnectionString("DefaultConnection")
            );

            return new AmbulanceWayDbContext(optionsBuilder.Options);
        }
    }
}
