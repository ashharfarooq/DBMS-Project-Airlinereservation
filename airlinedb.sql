CREATE DATABASE AirlineWEBDB;
GO

USE AirlineWEBDB;
GO

-- 1. Airports Table
IF OBJECT_ID('Airports', 'U') IS NULL
BEGIN
    CREATE TABLE Airports (
        AirportCode VARCHAR(10) PRIMARY KEY, 
        City VARCHAR(100) NOT NULL,
        Country VARCHAR(100) NOT NULL
    );
END
GO

-- 2. Passengers Table
IF OBJECT_ID('Passengers', 'U') IS NULL
BEGIN
    CREATE TABLE Passengers (
        PassengerID INT IDENTITY(1,1) PRIMARY KEY, 
        FullName VARCHAR(150) NOT NULL,
        Email VARCHAR(100) UNIQUE NOT NULL,
        Phone VARCHAR(20)
    );
END
GO

-- 3. Flights Table
IF OBJECT_ID('Flights', 'U') IS NULL
BEGIN
    CREATE TABLE Flights (
        FlightID INT IDENTITY(1,1) PRIMARY KEY,
        OriginCode VARCHAR(10) FOREIGN KEY REFERENCES Airports(AirportCode),
        DestinationCode VARCHAR(10) FOREIGN KEY REFERENCES Airports(AirportCode),
        FlightNumber VARCHAR(20) UNIQUE NOT NULL,
        DepartureTime DATETIME NOT NULL,
        ArrivalTime DATETIME NOT NULL,
        Capacity INT NOT NULL
    );
END
GO

-- 4. Bookings Table
IF OBJECT_ID('Bookings', 'U') IS NULL
BEGIN
    CREATE TABLE Bookings (
        BookingID INT IDENTITY(1,1) PRIMARY KEY,
        PassengerID INT FOREIGN KEY REFERENCES Passengers(PassengerID),
        FlightID INT FOREIGN KEY REFERENCES Flights(FlightID),
        BookingDate DATETIME DEFAULT GETDATE(),
        Status VARCHAR(20) DEFAULT 'Confirmed',
        CONSTRAINT UQ_Passenger_Flight UNIQUE(PassengerID, FlightID)
    );
END
GO

-- 5. Tickets Table
IF OBJECT_ID('Tickets', 'U') IS NULL
BEGIN
    CREATE TABLE Tickets (
        TicketID INT IDENTITY(1,1) PRIMARY KEY,
        BookingID INT UNIQUE FOREIGN KEY REFERENCES Bookings(BookingID),
        SeatNumber VARCHAR(10) NOT NULL,
        Price DECIMAL(10,2) CHECK (Price >= 0),
        IssueDate DATETIME DEFAULT GETDATE()
    );
END
GO

-- Seed Airports Data
MERGE INTO Airports AS target
USING (VALUES 
    ('KHI', 'Karachi', 'Pakistan'),
    ('LHE', 'Lahore', 'Pakistan'),
    ('ISB', 'Islamabad', 'Pakistan'),
    ('MUX', 'Multan', 'Pakistan'),
    ('PEW', 'Peshawar', 'Pakistan'),
    ('SKT', 'Sialkot', 'Pakistan')
) AS source (AirportCode, City, Country)
ON target.AirportCode = source.AirportCode
WHEN NOT MATCHED THEN
    INSERT (AirportCode, City, Country)
    VALUES (source.AirportCode, source.City, source.Country);
GO

-- Seed Flights Data
MERGE INTO Flights AS target
USING (VALUES 
    ('KHI', 'ISB', 'PK-300', '2026-10-10 08:00:00', '2026-10-10 10:00:00', 150),
    ('KHI', 'LHE', 'PK-302', '2026-10-11 14:00:00', '2026-10-11 15:45:00', 180),
    ('ISB', 'KHI', 'PK-301', '2026-10-12 18:00:00', '2026-10-12 20:00:00', 150),
    ('MUX', 'KHI', 'PK-211', '2026-10-20 06:00:00', '2026-10-20 08:30:00', 120),
    ('PEW', 'ISB', 'PK-741', '2026-10-21 14:00:00', '2026-10-21 18:30:00', 250),
    ('SKT', 'MUX', 'PK-739', '2026-10-22 20:00:00', '2026-10-23 01:00:00', 230),
    ('SKT', 'PEW', 'PK-799', '2026-10-22 10:00:00', '2026-10-23 01:00:00', 230),
    ('ISB', 'SKT', 'PK-901', '2026-10-12 15:00:00', '2026-10-12 20:00:00', 150)
) AS source (OriginCode, DestinationCode, FlightNumber, DepartureTime, ArrivalTime, Capacity)
ON target.FlightNumber = source.FlightNumber
WHEN NOT MATCHED THEN
    INSERT (OriginCode, DestinationCode, FlightNumber, DepartureTime, ArrivalTime, Capacity)
    VALUES (source.OriginCode, source.DestinationCode, source.FlightNumber, source.DepartureTime, source.ArrivalTime, source.Capacity);
GO

-- Stored Procedure: Safe Booking Execution
CREATE OR ALTER PROCEDURE sp_BookFlight
    @PassengerID INT,
    @FlightID INT,
    @SeatNumber VARCHAR(10),
    @Price DECIMAL(10,2)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @CurrentBookings INT;
    DECLARE @Capacity INT;
    
    SELECT @Capacity = Capacity FROM Flights WHERE FlightID = @FlightID;
    SELECT @CurrentBookings = COUNT(*) FROM Bookings WHERE FlightID = @FlightID AND Status = 'Confirmed';
    
    IF @CurrentBookings >= @Capacity
    BEGIN
        RAISERROR('Flight is fully booked.', 16, 1);
        RETURN;
    END;

    BEGIN TRY
        BEGIN TRANSACTION;
        
        DECLARE @NewBookingID INT;
        
        INSERT INTO Bookings (PassengerID, FlightID, BookingDate, Status)
        VALUES (@PassengerID, @FlightID, GETDATE(), 'Confirmed');
        
        SET @NewBookingID = SCOPE_IDENTITY();
        
        INSERT INTO Tickets (BookingID, SeatNumber, Price, IssueDate)
        VALUES (@NewBookingID, @SeatNumber, @Price, GETDATE());
        
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO
