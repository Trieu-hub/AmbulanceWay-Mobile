using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace AmbulanceWay.Migrations
{
    /// <inheritdoc />
    public partial class AddDriverDetails : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "AvailableEmergencyBeds",
                table: "Hospitals",
                type: "int",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<string>(
                name: "ReceptionStatus",
                table: "Hospitals",
                type: "nvarchar(20)",
                maxLength: 20,
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<string>(
                name: "StatusNote",
                table: "Hospitals",
                type: "nvarchar(300)",
                maxLength: 300,
                nullable: true);

            migrationBuilder.AddColumn<DateTime>(
                name: "StatusUpdatedAt",
                table: "Hospitals",
                type: "datetime2",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "TotalEmergencyBeds",
                table: "Hospitals",
                type: "int",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AlterColumn<decimal>(
                name: "PatientLng",
                table: "EmergencyCases",
                type: "decimal(10,7)",
                nullable: false,
                oldClrType: typeof(decimal),
                oldType: "decimal(18,2)");

            migrationBuilder.AlterColumn<decimal>(
                name: "PatientLat",
                table: "EmergencyCases",
                type: "decimal(10,7)",
                nullable: false,
                oldClrType: typeof(decimal),
                oldType: "decimal(18,2)");

            migrationBuilder.AddColumn<DateTime>(
                name: "AcceptedAt",
                table: "EmergencyCases",
                type: "datetime2",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "AssignedDriverName",
                table: "EmergencyCases",
                type: "nvarchar(100)",
                maxLength: 100,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "AssignedDriverUsername",
                table: "EmergencyCases",
                type: "nvarchar(100)",
                maxLength: 100,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "AssignedVehicleNo",
                table: "EmergencyCases",
                type: "nvarchar(20)",
                maxLength: 20,
                nullable: true);

            migrationBuilder.AddColumn<DateTime>(
                name: "CompletedAt",
                table: "EmergencyCases",
                type: "datetime2",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "ConfirmedHospitalId",
                table: "EmergencyCases",
                type: "int",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "DriverId",
                table: "EmergencyCases",
                type: "int",
                nullable: true);

            migrationBuilder.AddColumn<DateTime>(
                name: "PickedUpAt",
                table: "EmergencyCases",
                type: "datetime2",
                nullable: true);

            migrationBuilder.CreateTable(
                name: "HospitalNotifications",
                columns: table => new
                {
                    Id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    EmergencyCaseId = table.Column<int>(type: "int", nullable: false),
                    HospitalId = table.Column<int>(type: "int", nullable: false),
                    DriverName = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: false),
                    VehicleNo = table.Column<string>(type: "nvarchar(20)", maxLength: 20, nullable: false),
                    EtaMinutes = table.Column<int>(type: "int", nullable: false),
                    DriverLat = table.Column<decimal>(type: "decimal(10,7)", nullable: false),
                    DriverLng = table.Column<decimal>(type: "decimal(10,7)", nullable: false),
                    Status = table.Column<string>(type: "nvarchar(20)", maxLength: 20, nullable: false),
                    RejectReason = table.Column<string>(type: "nvarchar(300)", maxLength: 300, nullable: true),
                    AssignedRoom = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "datetime2", nullable: false),
                    RespondedAt = table.Column<DateTime>(type: "datetime2", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_HospitalNotifications", x => x.Id);
                    table.ForeignKey(
                        name: "FK_HospitalNotifications_EmergencyCases_EmergencyCaseId",
                        column: x => x.EmergencyCaseId,
                        principalTable: "EmergencyCases",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_HospitalNotifications_Hospitals_HospitalId",
                        column: x => x.HospitalId,
                        principalTable: "Hospitals",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "HospitalUsers",
                columns: table => new
                {
                    Id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    HospitalId = table.Column<int>(type: "int", nullable: false),
                    Username = table.Column<string>(type: "nvarchar(50)", maxLength: 50, nullable: false),
                    Password = table.Column<string>(type: "nvarchar(255)", maxLength: 255, nullable: false),
                    FullName = table.Column<string>(type: "nvarchar(100)", maxLength: 100, nullable: false),
                    Phone = table.Column<string>(type: "nvarchar(20)", maxLength: 20, nullable: true),
                    Status = table.Column<string>(type: "nvarchar(20)", maxLength: 20, nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "datetime2", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_HospitalUsers", x => x.Id);
                    table.ForeignKey(
                        name: "FK_HospitalUsers_Hospitals_HospitalId",
                        column: x => x.HospitalId,
                        principalTable: "Hospitals",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "PatientRatings",
                columns: table => new
                {
                    Id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    EmergencyCaseId = table.Column<int>(type: "int", nullable: false),
                    PatientProfileId = table.Column<int>(type: "int", nullable: false),
                    OverallRating = table.Column<int>(type: "int", nullable: false),
                    ResponseTimeRating = table.Column<int>(type: "int", nullable: false),
                    DriverAttitudeRating = table.Column<int>(type: "int", nullable: false),
                    VehicleConditionRating = table.Column<int>(type: "int", nullable: false),
                    SituationHandlingRating = table.Column<int>(type: "int", nullable: false),
                    Comment = table.Column<string>(type: "nvarchar(1000)", maxLength: 1000, nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "datetime2", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_PatientRatings", x => x.Id);
                    table.ForeignKey(
                        name: "FK_PatientRatings_EmergencyCases_EmergencyCaseId",
                        column: x => x.EmergencyCaseId,
                        principalTable: "EmergencyCases",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "IX_EmergencyCases_DriverId",
                table: "EmergencyCases",
                column: "DriverId");

            migrationBuilder.CreateIndex(
                name: "IX_EmergencyCases_PatientProfileId",
                table: "EmergencyCases",
                column: "PatientProfileId");

            migrationBuilder.CreateIndex(
                name: "IX_HospitalNotifications_EmergencyCaseId",
                table: "HospitalNotifications",
                column: "EmergencyCaseId");

            migrationBuilder.CreateIndex(
                name: "IX_HospitalNotifications_HospitalId",
                table: "HospitalNotifications",
                column: "HospitalId");

            migrationBuilder.CreateIndex(
                name: "IX_HospitalUsers_HospitalId",
                table: "HospitalUsers",
                column: "HospitalId");

            migrationBuilder.CreateIndex(
                name: "IX_HospitalUsers_Username",
                table: "HospitalUsers",
                column: "Username",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_PatientRatings_EmergencyCaseId",
                table: "PatientRatings",
                column: "EmergencyCaseId",
                unique: true);

            migrationBuilder.AddForeignKey(
                name: "FK_EmergencyCases_Drivers_DriverId",
                table: "EmergencyCases",
                column: "DriverId",
                principalTable: "Drivers",
                principalColumn: "Id",
                onDelete: ReferentialAction.SetNull);

            migrationBuilder.AddForeignKey(
                name: "FK_EmergencyCases_PatientProfiles_PatientProfileId",
                table: "EmergencyCases",
                column: "PatientProfileId",
                principalTable: "PatientProfiles",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_EmergencyCases_Drivers_DriverId",
                table: "EmergencyCases");

            migrationBuilder.DropForeignKey(
                name: "FK_EmergencyCases_PatientProfiles_PatientProfileId",
                table: "EmergencyCases");

            migrationBuilder.DropTable(
                name: "HospitalNotifications");

            migrationBuilder.DropTable(
                name: "HospitalUsers");

            migrationBuilder.DropTable(
                name: "PatientRatings");

            migrationBuilder.DropIndex(
                name: "IX_EmergencyCases_DriverId",
                table: "EmergencyCases");

            migrationBuilder.DropIndex(
                name: "IX_EmergencyCases_PatientProfileId",
                table: "EmergencyCases");

            migrationBuilder.DropColumn(
                name: "AvailableEmergencyBeds",
                table: "Hospitals");

            migrationBuilder.DropColumn(
                name: "ReceptionStatus",
                table: "Hospitals");

            migrationBuilder.DropColumn(
                name: "StatusNote",
                table: "Hospitals");

            migrationBuilder.DropColumn(
                name: "StatusUpdatedAt",
                table: "Hospitals");

            migrationBuilder.DropColumn(
                name: "TotalEmergencyBeds",
                table: "Hospitals");

            migrationBuilder.DropColumn(
                name: "AcceptedAt",
                table: "EmergencyCases");

            migrationBuilder.DropColumn(
                name: "AssignedDriverName",
                table: "EmergencyCases");

            migrationBuilder.DropColumn(
                name: "AssignedDriverUsername",
                table: "EmergencyCases");

            migrationBuilder.DropColumn(
                name: "AssignedVehicleNo",
                table: "EmergencyCases");

            migrationBuilder.DropColumn(
                name: "CompletedAt",
                table: "EmergencyCases");

            migrationBuilder.DropColumn(
                name: "ConfirmedHospitalId",
                table: "EmergencyCases");

            migrationBuilder.DropColumn(
                name: "DriverId",
                table: "EmergencyCases");

            migrationBuilder.DropColumn(
                name: "PickedUpAt",
                table: "EmergencyCases");

            migrationBuilder.AlterColumn<decimal>(
                name: "PatientLng",
                table: "EmergencyCases",
                type: "decimal(18,2)",
                nullable: false,
                oldClrType: typeof(decimal),
                oldType: "decimal(10,7)");

            migrationBuilder.AlterColumn<decimal>(
                name: "PatientLat",
                table: "EmergencyCases",
                type: "decimal(18,2)",
                nullable: false,
                oldClrType: typeof(decimal),
                oldType: "decimal(10,7)");
        }
    }
}
