-- DROP SCHEMA dbo;


-- CREATE SCHEMA dbo;
-- ParkingLot.dbo.PARKING_LOT definition


-- Drop table


-- DROP TABLE ParkingLot.dbo.PARKING_LOT;


CREATE TABLE PARKING_LOT
(
   ParkingLotID int IDENTITY(1,1) NOT NULL,
   Name nvarchar(100) COLLATE Chinese_Taiwan_Stroke_90_CI_AI NOT NULL,
   Address nvarchar(255) COLLATE Chinese_Taiwan_Stroke_90_CI_AI NULL,
   TotalSpaces int NOT NULL,
   HourlyRate int NOT NULL,
   CONSTRAINT PK__PARKING___6F271EA905DF3BCE PRIMARY KEY (ParkingLotID)
);




-- ParkingLot.dbo.PARKING_RECORD definition


-- Drop table


-- DROP TABLE ParkingLot.dbo.PARKING_RECORD;


CREATE TABLE PARKING_RECORD
(
   RecordID int IDENTITY(1,1) NOT NULL,
   ParkingLotID int NOT NULL,
   EntryTime datetime2 NOT NULL,
   ExitTime datetime2 NULL,
   TotalFee int NULL,
   PaidUntilTime DATETIME2 NULL,
   VehicleNumber nvarchar(8) COLLATE Chinese_Taiwan_Stroke_90_CI_AI NOT NULL,
   CONSTRAINT PK__PARKING___FBDF78C97041886D PRIMARY KEY (RecordID),
   CONSTRAINT FK_PARKING_RECORD_PARKING_LOT FOREIGN KEY (ParkingLotID) REFERENCES ParkingLot.dbo.PARKING_LOT(ParkingLotID)
);




-- ParkingLot.dbo.PAYMENT_RECORD definition


-- Drop table


-- DROP TABLE ParkingLot.dbo.PAYMENT_RECORD;


CREATE TABLE PAYMENT_RECORD
(
   PaymentID int IDENTITY(1,1) NOT NULL,
   RecordID int NOT NULL,
   PaymentAmount int NOT NULL,
   PaymentTime datetime2 NULL,
   PaymentMethod nvarchar(50) COLLATE Chinese_Taiwan_Stroke_90_CI_AI NULL,
   TransactionID nvarchar(100) COLLATE Chinese_Taiwan_Stroke_90_CI_AI NULL,
   CONSTRAINT PK__PAYMENT___9B556A58AB064CC0 PRIMARY KEY (PaymentID),
   CONSTRAINT FK_PAYMENT_RECORD_PARKING_RECORD FOREIGN KEY (RecordID) REFERENCES ParkingLot.dbo.PARKING_RECORD(RecordID)
);




-- ParkingLot.dbo.DISCOUNT definition


-- Drop table


-- DROP TABLE ParkingLot.dbo.DISCOUNT;


CREATE TABLE DISCOUNT
(
   Code nchar(12) COLLATE Chinese_Taiwan_Stroke_90_CI_AI NOT NULL,
   ValidTime datetime2 NULL,
   PaymentID int NULL,
   CONSTRAINT DISCOUNT_PK PRIMARY KEY (Code),
   CONSTRAINT DISCOUNT_PAYMENT_RECORD_FK FOREIGN KEY (PaymentID) REFERENCES ParkingLot.dbo.PAYMENT_RECORD(PaymentID)
);
