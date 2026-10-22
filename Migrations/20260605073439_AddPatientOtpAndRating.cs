using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace AmbulanceWay.Migrations
{
    /// <inheritdoc />
    public partial class AddPatientOtpAndRating : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "AttitudeRating",
                table: "TripHistories",
                type: "int",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "DriverNote",
                table: "TripHistories",
                type: "nvarchar(1000)",
                maxLength: 1000,
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "EmergencyCaseId",
                table: "TripHistories",
                type: "int",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "OverallRating",
                table: "TripHistories",
                type: "int",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "SituationRating",
                table: "TripHistories",
                type: "int",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "TimeRating",
                table: "TripHistories",
                type: "int",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "VehicleRating",
                table: "TripHistories",
                type: "int",
                nullable: true);

            migrationBuilder.CreateTable(
                name: "EmergencyCases",
                columns: table => new
                {
                    Id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    EmergencyType = table.Column<string>(type: "nvarchar(30)", maxLength: 30, nullable: false),
                    Description = table.Column<string>(type: "nvarchar(1000)", maxLength: 1000, nullable: false),
                    PatientAddress = table.Column<string>(type: "nvarchar(300)", maxLength: 300, nullable: false),
                    PatientLat = table.Column<decimal>(type: "decimal(18,2)", nullable: false),
                    PatientLng = table.Column<decimal>(type: "decimal(18,2)", nullable: false),
                    PatientProfileId = table.Column<int>(type: "int", nullable: false),
                    Status = table.Column<string>(type: "nvarchar(50)", maxLength: 50, nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "datetime2", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_EmergencyCases", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "OtpVerifications",
                columns: table => new
                {
                    Id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    PhoneNumber = table.Column<string>(type: "nvarchar(20)", maxLength: 20, nullable: false),
                    OtpCode = table.Column<string>(type: "nvarchar(10)", maxLength: 10, nullable: false),
                    ExpiresAt = table.Column<DateTime>(type: "datetime2", nullable: false),
                    UsedAt = table.Column<DateTime>(type: "datetime2", nullable: true),
                    Attempts = table.Column<int>(type: "int", nullable: false),
                    Purpose = table.Column<string>(type: "nvarchar(50)", maxLength: 50, nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "datetime2", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_OtpVerifications", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "PatientProfiles",
                columns: table => new
                {
                    Id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    FullName = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: false),
                    PhoneNumber = table.Column<string>(type: "nvarchar(20)", maxLength: 20, nullable: false),
                    BirthDate = table.Column<DateTime>(type: "datetime2", nullable: false),
                    Gender = table.Column<string>(type: "nvarchar(10)", maxLength: 10, nullable: false),
                    PermanentAddress = table.Column<string>(type: "nvarchar(300)", maxLength: 300, nullable: false),
                    MedicalHistory = table.Column<string>(type: "nvarchar(500)", maxLength: 500, nullable: true),
                    DrugAllergies = table.Column<string>(type: "nvarchar(500)", maxLength: 500, nullable: true),
                    EmergencyContactName = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: false),
                    EmergencyContactPhone = table.Column<string>(type: "nvarchar(20)", maxLength: 20, nullable: false),
                    IsOtpVerified = table.Column<bool>(type: "bit", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "datetime2", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "datetime2", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_PatientProfiles", x => x.Id);
                });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "EmergencyCases");

            migrationBuilder.DropTable(
                name: "OtpVerifications");

            migrationBuilder.DropTable(
                name: "PatientProfiles");

            migrationBuilder.DropColumn(
                name: "AttitudeRating",
                table: "TripHistories");

            migrationBuilder.DropColumn(
                name: "DriverNote",
                table: "TripHistories");

            migrationBuilder.DropColumn(
                name: "EmergencyCaseId",
                table: "TripHistories");

            migrationBuilder.DropColumn(
                name: "OverallRating",
                table: "TripHistories");

            migrationBuilder.DropColumn(
                name: "SituationRating",
                table: "TripHistories");

            migrationBuilder.DropColumn(
                name: "TimeRating",
                table: "TripHistories");

            migrationBuilder.DropColumn(
                name: "VehicleRating",
                table: "TripHistories");
        }
    }
}
