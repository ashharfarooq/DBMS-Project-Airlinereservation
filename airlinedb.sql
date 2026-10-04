USE AirlineWEBDB;
GO

-- 1. Independent Table: Aviation_Hubs
IF OBJECT_ID('Aviation_Hubs', 'U') IS NULL
BEGIN
    CREATE TABLE Aviation_Hubs (
        Hub_Code VARCHAR(10) PRIMARY KEY, 
        City VARCHAR(100) NOT NULL,
        Country VARCHAR(100) NOT NULL
    );
END
GO

-- 2. Independent Table: Travelers
IF OBJECT_ID('Travelers', 'U') IS NULL
BEGIN
    CREATE TABLE Travelers (
        Traveler_ID INT IDENTITY(1,1) PRIMARY KEY, 
        Full_Name VARCHAR(150) NOT NULL,
        Email_Address VARCHAR(100) UNIQUE NOT NULL,
        Contact_Number VARCHAR(20)
    );
END
GO

-- 3. Dependent Table: Flight_Schedules
IF OBJECT_ID('Flight_Schedules', 'U') IS NULL
BEGIN
    CREATE TABLE Flight_Schedules (
        Schedule_ID INT IDENTITY(1,1) PRIMARY KEY,
        Origin_Hub VARCHAR(10) FOREIGN KEY REFERENCES Aviation_Hubs(Hub_Code),
        Destination_Hub VARCHAR(10) FOREIGN KEY REFERENCES Aviation_Hubs(Hub_Code),
        Flight_Number VARCHAR(20) UNIQUE NOT NULL,
        Departure_Time DATETIME NOT NULL,
        Arrival_Time DATETIME NOT NULL,
        Total_Capacity INT NOT NULL
    );
END
GO

-- 4. Dependent Table: Reservations
IF OBJECT_ID('Reservations', 'U') IS NULL
BEGIN
    CREATE TABLE Reservations (
        Reservation_ID INT IDENTITY(1,1) PRIMARY KEY,
        Traveler_ID INT FOREIGN KEY REFERENCES Travelers(Traveler_ID),
        Schedule_ID INT FOREIGN KEY REFERENCES Flight_Schedules(Schedule_ID),
        Reservation_Date DATETIME DEFAULT GETDATE(),
        Status VARCHAR(20) DEFAULT 'Confirmed'
    );
END
GO

-- 5. Dependent Table: Boarding_Passes (Cleanly recreated without Cabin_Class errors)
DROP TABLE IF EXISTS Boarding_Passes;
GO

CREATE TABLE Boarding_Passes (
    Pass_ID INT IDENTITY(1,1) PRIMARY KEY,
    Reservation_ID INT FOREIGN KEY REFERENCES Reservations(Reservation_ID),
    Seat_Allocation VARCHAR(10) NOT NULL,
    Ticket_Price DECIMAL(10,2) NOT NULL,
    Issue_Date DATETIME DEFAULT GETDATE()
);
GO

-- 1. Upsert Aviation Hubs safely
MERGE INTO Aviation_Hubs AS target
USING (VALUES 
    ('KHI', 'Karachi', 'Pakistan'),
    ('LHE', 'Lahore', 'Pakistan'),
    ('ISB', 'Islamabad', 'Pakistan'),
    ('MUX', 'Multan', 'Pakistan'),
    ('PEW', 'Peshawar', 'Pakistan'),
    ('SKT', 'Sialkot', 'Pakistan')
) AS source (Hub_Code, City, Country)
ON target.Hub_Code = source.Hub_Code
WHEN NOT MATCHED THEN
    INSERT (Hub_Code, City, Country)
    VALUES (source.Hub_Code, source.City, source.Country);
GO

-- 2. Upsert Flight Schedules
MERGE INTO Flight_Schedules AS target
USING (VALUES 
    ('KHI', 'ISB', 'PK-300', '2026-10-10 08:00:00', '2026-10-10 10:00:00', 150),
    ('KHI', 'LHE', 'PK-302', '2026-10-11 14:00:00', '2026-10-11 15:45:00', 180),
    ('ISB', 'KHI', 'PK-301', '2026-10-12 18:00:00', '2026-10-12 20:00:00', 150),
    ('MUX', 'KHI', 'PK-211', '2026-10-20 06:00:00', '2026-10-20 08:30:00', 120),
    ('PEW', 'ISB', 'PK-741', '2026-10-21 14:00:00', '2026-10-21 18:30:00', 250),
    ('SKT', 'MUX', 'PK-739', '2026-10-22 20:00:00', '2026-10-23 01:00:00', 230),
    ('SKT', 'PEW', 'PK-799', '2026-10-22 10:00:00', '2026-10-23 01:00:00', 230),
    ('ISB', 'SKT', 'PK-901', '2026-10-12 15:00:00', '2026-10-12 20:00:00', 150)
) AS source (Origin_Hub, Destination_Hub, Flight_Number, Departure_Time, Arrival_Time, Total_Capacity)
ON target.Flight_Number = source.Flight_Number
WHEN NOT MATCHED THEN
    INSERT (Origin_Hub, Destination_Hub, Flight_Number, Departure_Time, Arrival_Time, Total_Capacity)
    VALUES (source.Origin_Hub, source.Destination_Hub, source.Flight_Number, source.Departure_Time, source.Arrival_Time, source.Total_Capacity);
GO

-- Clean up duplicate constraints/rows if any exist
IF EXISTS (SELECT * FROM sys.key_constraints WHERE name = 'UQ_Flight_Number')
BEGIN
    ALTER TABLE Flight_Schedules DROP CONSTRAINT UQ_Flight_Number;
END
GO

UPDATE r 
SET r.Schedule_ID = p.Min_Schedule_ID
FROM Reservations r
JOIN Flight_Schedules fs ON r.Schedule_ID = fs.Schedule_ID
JOIN (
    SELECT MIN(Schedule_ID) AS Min_Schedule_ID, Flight_Number
    FROM Flight_Schedules
    GROUP BY Flight_Number
) p ON fs.Flight_Number = p.Flight_Number
WHERE fs.Schedule_ID > p.Min_Schedule_ID;
GO

DELETE FROM Flight_Schedules 
WHERE Schedule_ID NOT IN (
    SELECT MIN(Schedule_ID) 
    FROM Flight_Schedules 
    GROUP BY Flight_Number
);
GO

ALTER TABLE Flight_Schedules ADD CONSTRAINT UQ_Flight_Number UNIQUE (Flight_Number);
GO

-- Cleanly drop and recreate the auto-generation trigger
DROP TRIGGER IF EXISTS trg_AutoGenerateTicket;
GO

CREATE TRIGGER trg_AutoGenerateTicket
ON Reservations
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO Boarding_Passes (Reservation_ID, Seat_Allocation, Ticket_Price)
    SELECT 
        i.Reservation_ID, 
        '12A', 
        15000.00
    FROM inserted i;
END;
GO

-- Backfill tickets for existing reservations that don't have one yet
INSERT INTO Boarding_Passes (Reservation_ID, Seat_Allocation, Ticket_Price)
SELECT r.Reservation_ID, '12A', 15000.00
FROM Reservations r
WHERE r.Reservation_ID NOT IN (SELECT Reservation_ID FROM Boarding_Passes);
GO

-- VIEW EVERYTHING CLEARLY IN SSMS RESULTS GRID
SELECT * FROM Aviation_Hubs;
SELECT * FROM Flight_Schedules;
SELECT * FROM Travelers;
SELECT * FROM Reservations;
SELECT * FROM Boarding_Passes;

-- CUSTOMER & TICKET JOIN VIEW
SELECT 
    t.Traveler_ID,
    t.Full_Name,
    t.Email_Address,
    r.Reservation_ID,
    r.Schedule_ID,
    bp.Pass_ID,
    bp.Seat_Allocation,
    bp.Ticket_Price
FROM Travelers t
JOIN Reservations r ON t.Traveler_ID = r.Traveler_ID
JOIN Boarding_Passes bp ON r.Reservation_ID = bp.Reservation_ID;
GO
