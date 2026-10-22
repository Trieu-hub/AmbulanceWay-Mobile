using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace AmbulanceWay.Migrations
{
    /// <inheritdoc />
    public partial class AddTripHistories : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "TripHistories",
                columns: table => new
                {
                    Id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    DriverName = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: false),
                    VehicleNo = table.Column<string>(type: "nvarchar(20)", maxLength: 20, nullable: false),
                    HospitalName = table.Column<string>(type: "nvarchar(200)", maxLength: 200, nullable: false),
                    HospitalAddress = table.Column<string>(type: "nvarchar(300)", maxLength: 300, nullable: true),
                    HospitalLat = table.Column<decimal>(type: "decimal(10,7)", nullable: false),
                    HospitalLng = table.Column<decimal>(type: "decimal(10,7)", nullable: false),
                    PatientAddress = table.Column<string>(type: "nvarchar(300)", maxLength: 300, nullable: false),
                    PatientLat = table.Column<decimal>(type: "decimal(10,7)", nullable: false),
                    PatientLng = table.Column<decimal>(type: "decimal(10,7)", nullable: false),
                    DistanceKm = table.Column<decimal>(type: "decimal(10,3)", nullable: false),
                    DurationMinutes = table.Column<int>(type: "int", nullable: false),
                    TripStatus = table.Column<string>(type: "nvarchar(50)", maxLength: 50, nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "datetime2", nullable: false),
                    CompletedAt = table.Column<DateTime>(type: "datetime2", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_TripHistories", x => x.Id);
                });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "TripHistories");
        }
    }
}
