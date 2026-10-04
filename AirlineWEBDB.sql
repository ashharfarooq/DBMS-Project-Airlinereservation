/* =====================================================================
   AirlineWEBDB - Airline Reservation System (SQL Server / T-SQL)

   WARNING: this script DROPS and RECREATES the whole AirlineWEBDB
   database, so every run starts from a clean state. Once your project
   holds real data, delete or comment out PART 0.

   Parts:
     0. Reset database
     1. Tables (with constraints and indexes)
     2. Stored procedures (users, flights, seats, booking, cancelling)
     3. Seed data (airports, flights, seats, demo users)
     4. Test examples (commented out)
   ===================================================================== */

/* ---------------------------------------------------------------------
   PART 0 - Reset database
   --------------------------------------------------------------------- */
CREATE DATABASE AirlineWEBDB;
GO

USE AirlineWEBDB;
GO

-- Required for filtered indexes to work inside stored procedures
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/* ---------------------------------------------------------------------
   PART 1 - Tables
   --------------------------------------------------------------------- */

-- 1. Airports
CREATE TABLE Airports (
    AirportCode CHAR(3)      NOT NULL,
    City        VARCHAR(100) NOT NULL,
    Country     VARCHAR(100) NOT NULL,
    CONSTRAINT PK_Airports PRIMARY KEY (AirportCode)
);
GO

-- 2. Users (login accounts). Passwords are stored as salted hashes, never as plain text.
CREATE TABLE Users (
    UserID           INT IDENTITY(1,1) NOT NULL,
    Email            VARCHAR(100)      NOT NULL,
    PasswordHash     VARBINARY(32)     NOT NULL,
    PasswordSalt     VARBINARY(16)     NOT NULL,
    Role             VARCHAR(20)       NOT NULL CONSTRAINT DF_Users_Role DEFAULT 'Customer',
    IsActive         BIT               NOT NULL CONSTRAINT DF_Users_IsActive DEFAULT 1,
    FailedLoginCount INT               NOT NULL CONSTRAINT DF_Users_FailedLogins DEFAULT 0,
    LockedUntil      DATETIME2(0)      NULL,
    LastLoginAt      DATETIME2(0)      NULL,
    CreatedAt        DATETIME2(0)      NOT NULL CONSTRAINT DF_Users_CreatedAt DEFAULT SYSDATETIME(),
    CONSTRAINT PK_Users PRIMARY KEY (UserID),
    CONSTRAINT UQ_Users_Email UNIQUE (Email),
    CONSTRAINT CK_Users_Role CHECK (Role IN ('Customer', 'Admin')),
    CONSTRAINT CK_Users_Email CHECK (Email LIKE '%_@_%._%')
);
GO

-- 3. Passengers (profile of a customer; linked to a login account)
CREATE TABLE Passengers (
    PassengerID INT IDENTITY(1,1) NOT NULL,
    UserID      INT               NULL,
    FullName    VARCHAR(150)      NOT NULL,
    Email       VARCHAR(100)      NOT NULL,
    Phone       VARCHAR(20)       NULL,
    CONSTRAINT PK_Passengers PRIMARY KEY (PassengerID),
    CONSTRAINT UQ_Passengers_Email UNIQUE (Email),
    CONSTRAINT FK_Passengers_User FOREIGN KEY (UserID) REFERENCES Users(UserID),
    CONSTRAINT CK_Passengers_Email CHECK (Email LIKE '%_@_%._%')
);
GO

-- One login account can own only one passenger profile
CREATE UNIQUE INDEX UX_Passengers_User
    ON Passengers (UserID)
    WHERE UserID IS NOT NULL;
GO

-- 4. Flights
CREATE TABLE Flights (
    FlightID        INT IDENTITY(1,1) NOT NULL,
    FlightNumber    VARCHAR(20)       NOT NULL,
    OriginCode      CHAR(3)           NOT NULL,
    DestinationCode CHAR(3)           NOT NULL,
    DepartureTime   DATETIME2(0)      NOT NULL,
    ArrivalTime     DATETIME2(0)      NOT NULL,
    Capacity        INT               NOT NULL,
    BasePrice       DECIMAL(10,2)     NOT NULL,   -- economy price; seats multiply it
    Status          VARCHAR(20)       NOT NULL CONSTRAINT DF_Flights_Status DEFAULT 'Scheduled',
    CONSTRAINT PK_Flights PRIMARY KEY (FlightID),
    CONSTRAINT UQ_Flights_Number UNIQUE (FlightNumber),
    CONSTRAINT FK_Flights_Origin FOREIGN KEY (OriginCode) REFERENCES Airports(AirportCode),
    CONSTRAINT FK_Flights_Destination FOREIGN KEY (DestinationCode) REFERENCES Airports(AirportCode),
    CONSTRAINT CK_Flights_Route CHECK (OriginCode <> DestinationCode),
    CONSTRAINT CK_Flights_Times CHECK (ArrivalTime > DepartureTime),
    CONSTRAINT CK_Flights_Capacity CHECK (Capacity > 0),
    CONSTRAINT CK_Flights_BasePrice CHECK (BasePrice >= 0),
    CONSTRAINT CK_Flights_Status CHECK (Status IN ('Scheduled', 'Cancelled', 'Departed'))
);
GO

CREATE INDEX IX_Flights_Search ON Flights (OriginCode, DestinationCode, DepartureTime);
GO

-- 5. Seats (every flight has its own list of seats)
CREATE TABLE Seats (
    FlightID        INT          NOT NULL,
    SeatNumber      VARCHAR(10)  NOT NULL,   -- e.g. 1A, 12C
    SeatClass       VARCHAR(20)  NOT NULL,
    PriceMultiplier DECIMAL(4,2) NOT NULL CONSTRAINT DF_Seats_Multiplier DEFAULT 1.00,
    CONSTRAINT PK_Seats PRIMARY KEY (FlightID, SeatNumber),
    CONSTRAINT FK_Seats_Flight FOREIGN KEY (FlightID) REFERENCES Flights(FlightID),
    CONSTRAINT CK_Seats_Class CHECK (SeatClass IN ('Economy', 'Business')),
    CONSTRAINT CK_Seats_Multiplier CHECK (PriceMultiplier > 0)
);
GO

-- 6. Bookings
CREATE TABLE Bookings (
    BookingID   INT IDENTITY(1,1) NOT NULL,
    PassengerID INT               NOT NULL,
    FlightID    INT               NOT NULL,
    BookingDate DATETIME2(0)      NOT NULL CONSTRAINT DF_Bookings_Date DEFAULT SYSDATETIME(),
    Status      VARCHAR(20)       NOT NULL CONSTRAINT DF_Bookings_Status DEFAULT 'Confirmed',
    CancelledAt DATETIME2(0)      NULL,
    CONSTRAINT PK_Bookings PRIMARY KEY (BookingID),
    CONSTRAINT UQ_Bookings_Booking_Flight UNIQUE (BookingID, FlightID),
    CONSTRAINT FK_Bookings_Passenger FOREIGN KEY (PassengerID) REFERENCES Passengers(PassengerID),
    CONSTRAINT FK_Bookings_Flight FOREIGN KEY (FlightID) REFERENCES Flights(FlightID),
    CONSTRAINT CK_Bookings_Status CHECK (Status IN ('Confirmed', 'Cancelled'))
);
GO

-- A passenger cannot hold two ACTIVE bookings on the same flight,
-- but may re-book after cancelling.
CREATE UNIQUE INDEX UX_Bookings_Passenger_Flight_Active
    ON Bookings (PassengerID, FlightID)
    WHERE Status = 'Confirmed';
GO

CREATE INDEX IX_Bookings_Flight    ON Bookings (FlightID, Status);
CREATE INDEX IX_Bookings_Passenger ON Bookings (PassengerID);
GO

-- 7. Tickets
CREATE TABLE Tickets (
    TicketID     INT IDENTITY(1,1) NOT NULL,
    BookingID    INT               NOT NULL,
    FlightID     INT               NOT NULL,
    SeatNumber   VARCHAR(10)       NOT NULL,
    Price        DECIMAL(10,2)     NOT NULL,
    Status       VARCHAR(20)       NOT NULL CONSTRAINT DF_Tickets_Status DEFAULT 'Active',
    IssueDate    DATETIME2(0)      NOT NULL CONSTRAINT DF_Tickets_Issue DEFAULT SYSDATETIME(),
    RefundAmount DECIMAL(10,2)     NULL,
    CONSTRAINT PK_Tickets PRIMARY KEY (TicketID),
    CONSTRAINT UQ_Tickets_Booking UNIQUE (BookingID),
    -- ticket must belong to a booking on the SAME flight
    CONSTRAINT FK_Tickets_Booking FOREIGN KEY (BookingID, FlightID) REFERENCES Bookings(BookingID, FlightID),
    -- seat must really exist on that flight
    CONSTRAINT FK_Tickets_Seat FOREIGN KEY (FlightID, SeatNumber) REFERENCES Seats(FlightID, SeatNumber),
    CONSTRAINT CK_Tickets_Price CHECK (Price >= 0),
    CONSTRAINT CK_Tickets_Status CHECK (Status IN ('Active', 'Cancelled'))
);
GO

-- The same seat cannot have two ACTIVE tickets (stops double seat booking)
CREATE UNIQUE INDEX UX_Tickets_ActiveSeat
    ON Tickets (FlightID, SeatNumber)
    WHERE Status = 'Active';
GO

/* ---------------------------------------------------------------------
   PART 2 - Stored procedures
   --------------------------------------------------------------------- */

-- Creates the seat map of a flight: 6 seats per row (A-F), rows 1-3 Business (2x price).
CREATE OR ALTER PROCEDURE usp_GenerateSeats
    @FlightID INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Capacity INT;

    SELECT @Capacity = Capacity FROM Flights WHERE FlightID = @FlightID;

    IF @Capacity IS NULL
        THROW 50010, 'Flight does not exist.', 1;

    -- Seats already created? Then do nothing.
    IF EXISTS (SELECT 1 FROM Seats WHERE FlightID = @FlightID)
        RETURN;

    ;WITH Numbers AS (
        SELECT TOP (@Capacity)
               CAST(ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS INT) AS SeatIndex
        FROM sys.all_objects a
        CROSS JOIN sys.all_objects b
    )
    INSERT INTO Seats (FlightID, SeatNumber, SeatClass, PriceMultiplier)
    SELECT @FlightID,
           CONCAT(((SeatIndex - 1) / 6) + 1, CHAR(65 + ((SeatIndex - 1) % 6))),
           CASE WHEN ((SeatIndex - 1) / 6) + 1 <= 3 THEN 'Business' ELSE 'Economy' END,
           CASE WHEN ((SeatIndex - 1) / 6) + 1 <= 3 THEN 2.00 ELSE 1.00 END
    FROM Numbers;
END;
GO

-- Admin: add a new flight and create its seats in one safe step.
CREATE OR ALTER PROCEDURE usp_AddFlight
    @FlightNumber    VARCHAR(20),
    @OriginCode      CHAR(3),
    @DestinationCode CHAR(3),
    @DepartureTime   DATETIME2(0),
    @ArrivalTime     DATETIME2(0),
    @Capacity        INT,
    @BasePrice       DECIMAL(10,2)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @NewFlightID INT;

        INSERT INTO Flights (FlightNumber, OriginCode, DestinationCode, DepartureTime, ArrivalTime, Capacity, BasePrice)
        VALUES (@FlightNumber, @OriginCode, @DestinationCode, @DepartureTime, @ArrivalTime, @Capacity, @BasePrice);

        SET @NewFlightID = SCOPE_IDENTITY();

        EXEC usp_GenerateSeats @FlightID = @NewFlightID;

        COMMIT TRANSACTION;

        SELECT @NewFlightID AS FlightID;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

-- Sign up: creates the login account and the passenger profile together.
CREATE OR ALTER PROCEDURE usp_RegisterUser
    @FullName VARCHAR(150),
    @Email    VARCHAR(100),
    @Phone    VARCHAR(20) = NULL,
    @Password NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Email = LOWER(LTRIM(RTRIM(@Email)));

    IF LEN(@Password) < 8
        THROW 50020, 'Password must be at least 8 characters.', 1;

    IF EXISTS (SELECT 1 FROM Users WHERE Email = @Email)
       OR EXISTS (SELECT 1 FROM Passengers WHERE Email = @Email)
        THROW 50021, 'This email is already registered.', 1;

    DECLARE @Salt VARBINARY(16) = CRYPT_GEN_RANDOM(16);
    DECLARE @Hash VARBINARY(32) = HASHBYTES('SHA2_256', @Salt + CONVERT(VARBINARY(200), @Password));
    DECLARE @NewUserID INT;
    DECLARE @NewPassengerID INT;

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO Users (Email, PasswordHash, PasswordSalt, Role)
        VALUES (@Email, @Hash, @Salt, 'Customer');

        SET @NewUserID = SCOPE_IDENTITY();

        INSERT INTO Passengers (UserID, FullName, Email, Phone)
        VALUES (@NewUserID, @FullName, @Email, @Phone);

        SET @NewPassengerID = SCOPE_IDENTITY();

        COMMIT TRANSACTION;

        SELECT @NewUserID AS UserID, @NewPassengerID AS PassengerID;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

-- Login: returns one row on success, raises an error otherwise.
-- Locks the account for 15 minutes after 5 wrong passwords in a row.
CREATE OR ALTER PROCEDURE usp_LoginUser
    @Email    VARCHAR(100),
    @Password NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SET @Email = LOWER(LTRIM(RTRIM(@Email)));

    DECLARE @UserID INT;
    DECLARE @StoredHash VARBINARY(32);
    DECLARE @Salt VARBINARY(16);
    DECLARE @IsActive BIT;
    DECLARE @LockedUntil DATETIME2(0);

    SELECT @UserID = UserID,
           @StoredHash = PasswordHash,
           @Salt = PasswordSalt,
           @IsActive = IsActive,
           @LockedUntil = LockedUntil
    FROM Users
    WHERE Email = @Email;

    -- Same message for unknown email and wrong password, so attackers cannot guess which emails exist
    IF @UserID IS NULL
        THROW 50030, 'Invalid email or password.', 1;

    IF @IsActive = 0
        THROW 50031, 'This account is disabled.', 1;

    IF @LockedUntil IS NOT NULL AND @LockedUntil > SYSDATETIME()
        THROW 50032, 'Account temporarily locked. Please try again later.', 1;

    -- Lock time finished: start counting from zero again
    IF @LockedUntil IS NOT NULL AND @LockedUntil <= SYSDATETIME()
        UPDATE Users SET FailedLoginCount = 0, LockedUntil = NULL WHERE UserID = @UserID;

    IF HASHBYTES('SHA2_256', @Salt + CONVERT(VARBINARY(200), @Password)) <> @StoredHash
    BEGIN
        UPDATE Users
        SET FailedLoginCount = FailedLoginCount + 1,
            LockedUntil = CASE WHEN FailedLoginCount + 1 >= 5
                               THEN DATEADD(MINUTE, 15, SYSDATETIME())
                               ELSE LockedUntil END
        WHERE UserID = @UserID;

        THROW 50030, 'Invalid email or password.', 1;
    END;

    UPDATE Users
    SET FailedLoginCount = 0, LockedUntil = NULL, LastLoginAt = SYSDATETIME()
    WHERE UserID = @UserID;

    SELECT u.UserID, p.PassengerID, u.Role, p.FullName, u.Email
    FROM Users u
    LEFT JOIN Passengers p ON p.UserID = u.UserID
    WHERE u.UserID = @UserID;
END;
GO

-- Search flights by route and date, with the number of free seats.
CREATE OR ALTER PROCEDURE usp_SearchFlights
    @Origin      CHAR(3),
    @Destination CHAR(3),
    @TravelDate  DATE
AS
BEGIN
    SET NOCOUNT ON;

    SELECT f.FlightID,
           f.FlightNumber,
           f.OriginCode,
           f.DestinationCode,
           f.DepartureTime,
           f.ArrivalTime,
           f.BasePrice,
           f.Capacity - taken.SeatsTaken AS AvailableSeats
    FROM Flights f
    CROSS APPLY (
        SELECT COUNT(*) AS SeatsTaken
        FROM Tickets t
        WHERE t.FlightID = f.FlightID AND t.Status = 'Active'
    ) taken
    WHERE f.OriginCode = @Origin
      AND f.DestinationCode = @Destination
      AND f.DepartureTime >= @TravelDate
      AND f.DepartureTime <  DATEADD(DAY, 1, @TravelDate)
      AND f.DepartureTime >  SYSDATETIME()
      AND f.Status = 'Scheduled'
    ORDER BY f.DepartureTime;
END;
GO

-- Seat selection: list the free seats of a flight with their prices.
CREATE OR ALTER PROCEDURE usp_GetAvailableSeats
    @FlightID INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT s.SeatNumber,
           s.SeatClass,
           CAST(f.BasePrice * s.PriceMultiplier AS DECIMAL(10,2)) AS Price
    FROM Seats s
    JOIN Flights f ON f.FlightID = s.FlightID
    WHERE s.FlightID = @FlightID
      AND NOT EXISTS (
            SELECT 1
            FROM Tickets t
            WHERE t.FlightID = s.FlightID
              AND t.SeatNumber = s.SeatNumber
              AND t.Status = 'Active')
    ORDER BY CAST(LEFT(s.SeatNumber, LEN(s.SeatNumber) - 1) AS INT),
             RIGHT(s.SeatNumber, 1);
END;
GO

-- Book a flight with a chosen seat. The price comes from the database, not from the caller.
CREATE OR ALTER PROCEDURE usp_BookFlight
    @PassengerID INT,
    @FlightID    INT,
    @SeatNumber  VARCHAR(10)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @DepartureTime DATETIME2(0);
    DECLARE @FlightStatus  VARCHAR(20);
    DECLARE @BasePrice     DECIMAL(10,2);
    DECLARE @Multiplier    DECIMAL(4,2);
    DECLARE @Price         DECIMAL(10,2);
    DECLARE @NewBookingID  INT;
    DECLARE @NewTicketID   INT;

    SET @SeatNumber = UPPER(LTRIM(RTRIM(@SeatNumber)));

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT @DepartureTime = DepartureTime,
               @FlightStatus  = Status,
               @BasePrice     = BasePrice
        FROM Flights
        WHERE FlightID = @FlightID;

        IF @FlightStatus IS NULL
            THROW 50040, 'Flight does not exist.', 1;

        IF @FlightStatus <> 'Scheduled' OR @DepartureTime <= SYSDATETIME()
            THROW 50041, 'This flight is not open for booking.', 1;

        IF NOT EXISTS (SELECT 1 FROM Passengers WHERE PassengerID = @PassengerID)
            THROW 50042, 'Passenger does not exist.', 1;

        -- Lock this seat row: if two people click the same seat at the same moment,
        -- the second one waits here until the first one finishes.
        SELECT @Multiplier = PriceMultiplier
        FROM Seats WITH (UPDLOCK, HOLDLOCK)
        WHERE FlightID = @FlightID AND SeatNumber = @SeatNumber;

        IF @Multiplier IS NULL
            THROW 50043, 'This seat does not exist on the selected flight.', 1;

        IF EXISTS (SELECT 1 FROM Tickets
                   WHERE FlightID = @FlightID AND SeatNumber = @SeatNumber AND Status = 'Active')
            THROW 50044, 'This seat is already taken.', 1;

        IF EXISTS (SELECT 1 FROM Bookings
                   WHERE PassengerID = @PassengerID AND FlightID = @FlightID AND Status = 'Confirmed')
            THROW 50045, 'You already have a confirmed booking on this flight.', 1;

        SET @Price = CAST(@BasePrice * @Multiplier AS DECIMAL(10,2));

        INSERT INTO Bookings (PassengerID, FlightID, Status)
        VALUES (@PassengerID, @FlightID, 'Confirmed');

        SET @NewBookingID = SCOPE_IDENTITY();

        INSERT INTO Tickets (BookingID, FlightID, SeatNumber, Price)
        VALUES (@NewBookingID, @FlightID, @SeatNumber, @Price);

        SET @NewTicketID = SCOPE_IDENTITY();

        COMMIT TRANSACTION;

        SELECT @NewBookingID AS BookingID,
               @NewTicketID  AS TicketID,
               @SeatNumber   AS SeatNumber,
               @Price        AS Price;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

-- Cancel a booking. The seat becomes free again and the refund is calculated:
--   more than 48 hours before departure -> 100% refund
--   24 to 48 hours before departure     -> 50% refund
--   less than 24 hours                  -> no refund
-- (change these rules to match your project requirements)
CREATE OR ALTER PROCEDURE usp_CancelBooking
    @BookingID   INT,
    @PassengerID INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @OwnerID       INT;
    DECLARE @BookingStatus VARCHAR(20);
    DECLARE @FlightID      INT;
    DECLARE @DepartureTime DATETIME2(0);
    DECLARE @Price         DECIMAL(10,2);
    DECLARE @Refund        DECIMAL(10,2);

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT @OwnerID = PassengerID,
               @BookingStatus = Status,
               @FlightID = FlightID
        FROM Bookings WITH (UPDLOCK)
        WHERE BookingID = @BookingID;

        -- Same message for "not found" and "not yours", so other people's bookings stay private
        IF @OwnerID IS NULL OR @OwnerID <> @PassengerID
            THROW 50050, 'Booking not found.', 1;

        IF @BookingStatus = 'Cancelled'
            THROW 50051, 'This booking is already cancelled.', 1;

        SELECT @DepartureTime = DepartureTime FROM Flights WHERE FlightID = @FlightID;

        IF @DepartureTime <= SYSDATETIME()
            THROW 50052, 'A flight that has already departed cannot be cancelled.', 1;

        SELECT @Price = Price
        FROM Tickets
        WHERE BookingID = @BookingID AND Status = 'Active';

        SET @Refund = CAST(
            CASE WHEN @DepartureTime > DATEADD(HOUR, 48, SYSDATETIME()) THEN @Price
                 WHEN @DepartureTime > DATEADD(HOUR, 24, SYSDATETIME()) THEN @Price * 0.50
                 ELSE 0 END AS DECIMAL(10,2));

        UPDATE Bookings
        SET Status = 'Cancelled', CancelledAt = SYSDATETIME()
        WHERE BookingID = @BookingID;

        UPDATE Tickets
        SET Status = 'Cancelled', RefundAmount = @Refund
        WHERE BookingID = @BookingID AND Status = 'Active';

        COMMIT TRANSACTION;

        SELECT @BookingID AS BookingID, 'Cancelled' AS Status, @Refund AS RefundAmount;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

-- "My bookings" page.
CREATE OR ALTER PROCEDURE usp_GetPassengerBookings
    @PassengerID INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT b.BookingID,
           b.Status AS BookingStatus,
           b.BookingDate,
           f.FlightNumber,
           f.OriginCode,
           f.DestinationCode,
           f.DepartureTime,
           f.ArrivalTime,
           t.SeatNumber,
           t.Price,
           t.RefundAmount
    FROM Bookings b
    JOIN Flights f ON f.FlightID = b.FlightID
    JOIN Tickets t ON t.BookingID = b.BookingID
    WHERE b.PassengerID = @PassengerID
    ORDER BY f.DepartureTime DESC;
END;
GO

/* ---------------------------------------------------------------------
   PART 3 - Seed data
   --------------------------------------------------------------------- */

MERGE INTO Airports AS target
USING (VALUES
    ('KHI', 'Karachi',   'Pakistan'),
    ('LHE', 'Lahore',    'Pakistan'),
    ('ISB', 'Islamabad', 'Pakistan'),
    ('MUX', 'Multan',    'Pakistan'),
    ('PEW', 'Peshawar',  'Pakistan'),
    ('SKT', 'Sialkot',   'Pakistan')
) AS source (AirportCode, City, Country)
ON target.AirportCode = source.AirportCode
WHEN NOT MATCHED THEN
    INSERT (AirportCode, City, Country)
    VALUES (source.AirportCode, source.City, source.Country);
GO

-- Flight times and prices (PKR) are sample values for testing
MERGE INTO Flights AS target
USING (VALUES
    ('PK-300', 'KHI', 'ISB', '2026-10-10 08:00:00', '2026-10-10 10:00:00', 150, 22000.00),
    ('PK-302', 'KHI', 'LHE', '2026-10-11 14:00:00', '2026-10-11 15:45:00', 180, 20000.00),
    ('PK-301', 'ISB', 'KHI', '2026-10-12 18:00:00', '2026-10-12 20:00:00', 150, 22000.00),
    ('PK-211', 'MUX', 'KHI', '2026-10-20 06:00:00', '2026-10-20 07:15:00', 120, 15000.00),
    ('PK-741', 'PEW', 'ISB', '2026-10-21 14:00:00', '2026-10-21 14:50:00', 250,  9000.00),
    ('PK-739', 'SKT', 'MUX', '2026-10-22 20:00:00', '2026-10-22 21:20:00', 230, 12000.00),
    ('PK-799', 'SKT', 'PEW', '2026-10-22 10:00:00', '2026-10-22 11:05:00', 230, 14000.00),
    ('PK-901', 'ISB', 'SKT', '2026-10-12 15:00:00', '2026-10-12 15:55:00', 150, 11000.00)
) AS source (FlightNumber, OriginCode, DestinationCode, DepartureTime, ArrivalTime, Capacity, BasePrice)
ON target.FlightNumber = source.FlightNumber
WHEN NOT MATCHED THEN
    INSERT (FlightNumber, OriginCode, DestinationCode, DepartureTime, ArrivalTime, Capacity, BasePrice)
    VALUES (source.FlightNumber, source.OriginCode, source.DestinationCode,
            source.DepartureTime, source.ArrivalTime, source.Capacity, source.BasePrice);
GO

-- Create the seat map for every flight
DECLARE @CurrentFlightID INT = (SELECT MIN(FlightID) FROM Flights);

WHILE @CurrentFlightID IS NOT NULL
BEGIN
    EXEC usp_GenerateSeats @FlightID = @CurrentFlightID;

    SELECT @CurrentFlightID = MIN(FlightID)
    FROM Flights
    WHERE FlightID > @CurrentFlightID;
END;
GO

-- Demo admin account (CHANGE THIS PASSWORD before using the project for real)
DECLARE @AdminSalt VARBINARY(16) = CRYPT_GEN_RANDOM(16);
DECLARE @AdminPassword NVARCHAR(100) = N'Admin@12345';

INSERT INTO Users (Email, PasswordHash, PasswordSalt, Role)
VALUES ('admin@airline.com',
        HASHBYTES('SHA2_256', @AdminSalt + CONVERT(VARBINARY(200), @AdminPassword)),
        @AdminSalt,
        'Admin');
GO

-- Demo customer account for testing
EXEC usp_RegisterUser
    @FullName = 'Demo Passenger',
    @Email    = 'demo@example.com',
    @Phone    = '0300-0000000',
    @Password = N'Demo@12345';
GO

  /* ---------------------------------------------------------------------
   --PART 4 - Test examples (remove the comment markers to try them)
   ---------------------------------------------------------------------

-- Log in
EXEC usp_LoginUser @Email = 'demo@example.com', @Password = N'Demo@12345';

-- Search flights from Karachi to Islamabad on 10 Oct 2026
EXEC usp_SearchFlights @Origin = 'KHI', @Destination = 'ISB', @TravelDate = '2026-10-10';

-- See free seats on flight 1
EXEC usp_GetAvailableSeats @FlightID = 1;

-- Book seat 5C on flight 1 for passenger 1
EXEC usp_BookFlight @PassengerID = 1, @FlightID = 1, @SeatNumber = '5C';

-- Try the same seat again -> error "This seat is already taken."
EXEC usp_BookFlight @PassengerID = 1, @FlightID = 1, @SeatNumber = '5C';

-- My bookings
EXEC usp_GetPassengerBookings @PassengerID = 1;

-- Cancel booking 1 (then seat 5C is free again)
EXEC usp_CancelBooking @BookingID = 1, @PassengerID = 1;

   --------------------------------------------------------------------- */
