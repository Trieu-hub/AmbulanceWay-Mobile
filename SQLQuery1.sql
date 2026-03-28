CREATE TABLE [dbo].[AmbulanceTrips](
    [Id] INT IDENTITY(1,1) NOT NULL,
    [StaffName] NVARCHAR(100) NOT NULL,
    [Hospital] NVARCHAR(200) NOT NULL,
    [VehicleNo] NVARCHAR(50) NOT NULL,
    [ShiftStart] DATETIME2(7) NOT NULL,
    [ShiftEnd] DATETIME2(7) NULL,
    [IncidentAddress] NVARCHAR(300) NOT NULL,

    [IncidentLat] DECIMAL(10,7) NOT NULL,
    [IncidentLng] DECIMAL(10,7) NOT NULL,

    [HospitalAddress] NVARCHAR(300) NOT NULL,
    [HospitalLat] DECIMAL(10,7) NOT NULL,
    [HospitalLng] DECIMAL(10,7) NOT NULL,

    [DistanceKm] DECIMAL(10,3) NOT NULL,

    [EstimatedMinutes] INT NOT NULL,
    [CreatedAt] DATETIME2(7) NOT NULL 
        CONSTRAINT DF_AmbulanceTrips_CreatedAt DEFAULT (SYSDATETIME()),

    CONSTRAINT PK_AmbulanceTrips PRIMARY KEY CLUSTERED ([Id] ASC)
);
