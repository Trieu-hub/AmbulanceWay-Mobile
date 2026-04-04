CREATE DATABASE AmbulanceSystem;
GO

USE AmbulanceSystem;
GO

CREATE TABLE Users (
    Id INT IDENTITY(1,1) PRIMARY KEY,
    Username NVARCHAR(50) UNIQUE NOT NULL,
    Password NVARCHAR(255) NOT NULL,
    Role NVARCHAR(20) DEFAULT 'STAFF',
    Status NVARCHAR(20) DEFAULT 'ACTIVE',
    IsOnline BIT DEFAULT 0,
    CreatedAt DATETIME2 DEFAULT SYSDATETIME()
);

CREATE TABLE Ambulances (
    Id INT IDENTITY(1,1) PRIMARY KEY,
    VehicleNo NVARCHAR(50) NOT NULL UNIQUE,
    Status NVARCHAR(20) DEFAULT 'AVAILABLE',
    CreatedAt DATETIME2 DEFAULT SYSDATETIME()
);

CREATE TABLE Hospitals (
    Id INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(200) NOT NULL,
    Address NVARCHAR(300) NOT NULL,
    Lat DECIMAL(10,7),
    Lng DECIMAL(10,7)
);

CREATE TABLE Incidents (
    Id INT IDENTITY(1,1) PRIMARY KEY,
    Address NVARCHAR(300) NOT NULL,
    Lat DECIMAL(10,7) NOT NULL,
    Lng DECIMAL(10,7) NOT NULL,
    Description NVARCHAR(500),
    CreatedAt DATETIME2 DEFAULT SYSDATETIME()
);

CREATE TABLE AmbulanceTrips (
    Id INT IDENTITY(1,1) PRIMARY KEY,
    UserId INT NOT NULL,
    AmbulanceId INT NOT NULL,
    IncidentId INT NOT NULL,
    HospitalId INT NOT NULL,
    ShiftStart DATETIME2 NOT NULL,
    ShiftEnd DATETIME2 NULL,
    DistanceKm DECIMAL(10,3),
    EstimatedMinutes INT,
    Status NVARCHAR(20) DEFAULT 'PROCESSING',
    CreatedAt DATETIME2 DEFAULT SYSDATETIME(),
    FOREIGN KEY (UserId) REFERENCES Users(Id),
    FOREIGN KEY (AmbulanceId) REFERENCES Ambulances(Id),
    FOREIGN KEY (IncidentId) REFERENCES Incidents(Id),
    FOREIGN KEY (HospitalId) REFERENCES Hospitals(Id)
);

CREATE INDEX IDX_Hospitals_Location ON Hospitals(Lat, Lng);
CREATE INDEX IDX_Trips_Status ON AmbulanceTrips(Status);

INSERT INTO Hospitals (Name, Address, Lat, Lng) VALUES
(N'Bệnh viện Chợ Rẫy', N'201B Nguyễn Chí Thanh, Quận 5', 10.754, 106.663),
(N'Bệnh viện 115', N'527 Sư Vạn Hạnh, Quận 10', 10.774, 106.667),
(N'Bệnh viện Đại học Y Dược', N'215 Hồng Bàng, Quận 5', 10.756, 106.660),
(N'Bệnh viện Nhân dân Gia Định', N'1 Nơ Trang Long, Bình Thạnh', 10.800, 106.699),
(N'Bệnh viện Thủ Đức', N'29 Phú Châu, Thủ Đức', 10.850, 106.770),
(N'Bệnh viện Quận 1', N'338 Hai Bà Trưng, Quận 1', 10.782, 106.695),
(N'Bệnh viện Quận 7', N'101 Nguyễn Thị Thập, Quận 7', 10.732, 106.722);

DECLARE @lat FLOAT = 10.76;
DECLARE @lng FLOAT = 106.68;

SELECT TOP 1 *,
(
    6371 * ACOS(
        COS(RADIANS(@lat)) * COS(RADIANS(Lat)) *
        COS(RADIANS(Lng) - RADIANS(@lng)) +
        SIN(RADIANS(@lat)) * SIN(RADIANS(Lat))
    )
) AS DistanceKm
FROM Hospitals
ORDER BY DistanceKm ASC;