CREATE DATABASE AirlineReservationSystemDB
USE AirlineReservationSystemDB
-- Create Airport Table
CREATE TABLE Airport (
    Airport_code VARCHAR(10) PRIMARY KEY,
    City VARCHAR(100) NOT NULL,
    Country VARCHAR(100) NOT NULL
);

-- Create Passenger Table
CREATE TABLE Passenger (
    Passenger_id INT PRIMARY KEY IDENTITY(1,1),
    Full_Name VARCHAR(100) NOT NULL,
    Email VARCHAR(100) UNIQUE NOT NULL,
    Phone_number VARCHAR(20)
);

-- Create Flights Table
CREATE TABLE Flights (
    Flight_id INT PRIMARY KEY IDENTITY(1,1),
    Flight_number VARCHAR(20) NOT NULL,
    Departure_time DATETIME NOT NULL,
    Arrival_Time DATETIME NOT NULL,
    Total_Seats INT NOT NULL,
    Departure_ap VARCHAR(10) NOT NULL,
    Arrival_ap VARCHAR(10) NOT NULL,
    FOREIGN KEY (Departure_ap) REFERENCES Airport(Airport_code),
    FOREIGN KEY (Arrival_ap) REFERENCES Airport(Airport_code)
);

-- Create Booking Table
CREATE TABLE Booking (
    Booking_id INT PRIMARY KEY IDENTITY(1,1),
    Passenger_id INT NOT NULL,
    Flight_id INT NOT NULL,
    Booking_date DATE NOT NULL,
    Status VARCHAR(20) DEFAULT 'Confirmed',
    FOREIGN KEY (Passenger_id) REFERENCES Passenger(Passenger_id),
    FOREIGN KEY (Flight_id) REFERENCES Flights(Flight_id)
);

-- Create Tickets Table
CREATE TABLE Tickets (
    Ticket_id INT PRIMARY KEY IDENTITY(1,1),
    Booking_id INT NOT NULL,
    Class VARCHAR(20) CHECK (Class IN ('Economy', 'Business', 'First')),
    Price DECIMAL(10, 2) NOT NULL,
    Issue_Date DATE NOT NULL,
    Seat_number VARCHAR(10) NOT NULL,
    FOREIGN KEY (Booking_id) REFERENCES Booking(Booking_id)
);
-- 1. Insert Airports
INSERT INTO Airport (Airport_code, City, Country) VALUES
('KHI', 'Karachi', 'Pakistan'),
('LHE', 'Lahore', 'Pakistan'),
('ISB', 'Islamabad', 'Pakistan'),
('DXB', 'Dubai', 'UAE');

-- 2. Insert Passengers
INSERT INTO Passenger (Full_Name, Email, Phone_number) VALUES
('Ali Khan', 'ali.khan@email.com', '03001234567'),
('Sara Ahmed', 'sara.a@email.com', '03129876543'),
('Usman Tariq', 'usman.t@email.com', '03335551122');

-- 3. Insert Flights
INSERT INTO Flights (Flight_number, Departure_time, Arrival_Time, Total_Seats, Departure_ap, Arrival_ap) VALUES
('PK-301', '2026-10-01 08:00:00', '2026-10-01 10:00:00', 180, 'KHI', 'LHE'),
('PK-302', '2026-10-01 12:00:00', '2026-10-01 14:00:00', 150, 'LHE', 'ISB'),
('EK-605', '2026-10-02 03:00:00', '2026-10-02 05:30:00', 250, 'KHI', 'DXB');

-- 4. Insert Bookings
INSERT INTO Booking (Passenger_id, Flight_id, Booking_date, Status) VALUES
(1, 1, '2026-09-15', 'Confirmed'),
(2, 1, '2026-09-16', 'Confirmed'),
(3, 3, '2026-09-18', 'Confirmed');

-- 5. Insert Tickets
INSERT INTO Tickets (Booking_id, Class, Price, Issue_Date, Seat_number) VALUES
(1, 'Economy', 25000.00, '2026-09-15', '12A'),
(2, 'Business', 45000.00, '2026-09-16', '02C'),
(3, 'Economy', 65000.00, '2026-09-18', '18B');

