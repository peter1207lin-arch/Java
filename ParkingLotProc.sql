-- 隨機產生12位折扣碼，並記錄產出時間與有效日期（產出時間+2小時）
DROP proc IF EXISTS generateCode
go
Create PROC generateCode
AS
BEGIN
   DECLARE @DiscountCode NCHAR(12)
   DECLARE @ValidTime DATETIME2
   DECLARE @Inserted INT = 0;


   WHILE @Inserted = 0
   BEGIN
       SET @DiscountCode = LEFT(REPLACE(CONVERT(NCHAR(36), NEWID()), '-', ''), 12)
       SET @ValidTime = DATEADD(HOUR, 2, GETDATE())
       BEGIN try
   INSERT INTO DISCOUNT
           (Code, PaymentID, ValidTime)
       VALUES
           (@DiscountCode, NULL, @ValidTime)
   SET @Inserted = 1
   END TRY
   BEGIN CATCH
   END CATCH
   END
END


-- 計算剩餘空位
DROP PROC IF EXISTS getAvailableSpaces
GO
CREATE PROC getAvailableSpaces
   @ParkingLotID INT,
   @AvailableSpaces INT OUTPUT
-- 新增 OUTPUT 參數
AS
BEGIN
   SELECT
       @AvailableSpaces = p.TotalSpaces - ISNULL(COUNT (r.RecordID), 0)
   FROM PARKING_LOT P
       LEFT JOIN PARKING_RECORD r
       ON p.ParkingLotID = r.ParkingLotID
           AND r.ExitTime IS NULL
   WHERE p.ParkingLotID = @ParkingLotID
   GROUP BY p.ParkingLotID, p.TotalSpaces;
END
GO


-- 車輛入場
DROP PROCEDURE IF EXISTS vehicleEntry;
GO
CREATE PROCEDURE vehicleEntry
   @VehicleNumber NVARCHAR(8),
   @ParkingLotID INT
AS
BEGIN
   DECLARE @AvailableSpaces INT


   EXEC getAvailableSpaces
   @ParkingLotID,
   @AvailableSpaces = @AvailableSpaces OUTPUT;


   IF @AvailableSpaces <= 0
  BEGIN
       RAISERROR(N'停車場已滿，無法入場。', 16, 1);
       RETURN;
   END


   -- 新增進場紀錄並取得入場時間
   DECLARE @EntryTime DATETIME2(3) = GETDATE();
   INSERT INTO PARKING_RECORD
       (VehicleNumber, EntryTime, ParkingLotID)
   VALUES
       (@VehicleNumber, @EntryTime, @ParkingLotID);




   -- 印出車輛的入場停車場、入場時間、車牌號碼（此語句必須在儲存過程內部）
   SELECT @ParkingLotID AS 停車場ID, @EntryTime AS 入場時間, @VehicleNumber AS 車牌號碼;
END
GO


-- 計算停車折扣前金額
DROP PROCEDURE IF EXISTS CalParkingFee
GO
CREATE PROCEDURE CalParkingFee
   @VehicleNumber NVARCHAR(8)
AS
BEGIN
   SET NOCOUNT ON;
   DECLARE @paiduntiltime DATETIME2
   DECLARE @RecordID INT, @ParkingLotID INT, @EntryTime DATETIME2(3), @ExitTime DATETIME2(3);
   DECLARE @Minutes INT, @Hours INT, @HourlyRate INT;
   DECLARE @Fee INT
   -- 取得最新一筆該車牌的停車紀錄
   SELECT TOP 1
       @RecordID = RecordID,
       @ParkingLotID = ParkingLotID,
       @EntryTime = EntryTime,
       @ExitTime = ExitTime,
       @paiduntiltime = PaidUntilTime
   FROM PARKING_RECORD
   WHERE VehicleNumber = @VehicleNumber
   ORDER BY ExitTime DESC;


   IF @RecordID is NULL
   BEGIN
       RAISERROR('查無此車牌', 16, 1)
       RETURN
   END


   -- 預防重複計算
   IF NOT EXISTS (SELECT 1
   FROM PAYMENT_RECORD
   WHERE RecordID = @RecordID and PaymentTime is NULL)
   BEGIN
       -- 取得停車場每小時費率
       SELECT @HourlyRate = HourlyRate
       FROM PARKING_LOT
       WHERE ParkingLotID = @ParkingLotID;
       -- 計算停車總分鐘
       IF @paiduntiltime IS NULL
           BEGIN
           SET @Minutes = DATEDIFF(MINUTE, @EntryTime, GETDATE());
           PRINT(1)
           END
       ELSE IF @paiduntiltime is not null and @paiduntiltime > GETDATE()
       BEGIN
           PRINT('已繳完費可以直接離場')
           PRINT(2)
           RETURN
       END
       ELSE
           BEGIN
           PRINT(3)
           SET @Minutes = DATEDIFF(MINUTE, @paiduntiltime, GETDATE());
           END


       -- 四捨五入到小時
       SET @Hours = CEILING(@Minutes / 60.0);
       -- 計算原始費用
       SET @Fee = @Hours * @HourlyRate;
       -- 把需繳金額插入表格中
       INSERT INTO PAYMENT_RECORD
           (RecordID, PaymentAmount)
       VALUES
           (@RecordID, @Fee)
   END
END


-- 使用優惠券
DROP PROCEDURE IF EXISTS UseCupong
GO
CREATE PROCEDURE UseCupong
   @VehicleNumber NVARCHAR(8),
   @Code NCHAR(12)
AS
BEGIN
   DECLARE @Fee INT
   DECLARE @RecordID INT
   DECLARE @ParkingLotID INT
   DECLARE @HourlyRate INT
   DECLARE @PaymentID INT
   DECLARE @FinalFee INT
   IF EXISTS (SELECT 1
   FROM DISCOUNT
   WHERE Code = @Code and PaymentID is NULL AND GETDATE() <= ValidTime)
   BEGIN
       SELECT TOP 1
           @RecordID = RecordID,
           @ParkingLotID = ParkingLotID
       FROM PARKING_RECORD
       WHERE VehicleNumber = @VehicleNumber
           AND ExitTime is NULL
       ORDER BY ExitTime DESC;


       SELECT @Fee = PaymentAmount, @PaymentID = PaymentID
       FROM PAYMENT_RECORD
       WHERE RecordID = @RecordID
       IF @Fee > 0
       BEGIN
           SELECT @HourlyRate = HourlyRate
           FROM PARKING_LOT
           WHERE ParkingLotID = @ParkingLotID
           IF @Fee - @HourlyRate > 0
               SET @FinalFee = @Fee - @HourlyRate
           ELSE
               SET @FinalFee = 0
           BEGIN TRY
               BEGIN TRANSACTION
           UPDATE PAYMENT_RECORD SET PaymentAmount = @FinalFee WHERE PaymentID = @PaymentID
           UPDATE DISCOUNT SET PaymentID = @PaymentID WHERE Code = @Code
               COMMIT TRANSACTION
                       END TRY
           BEGIN CATCH
                           ROLLBACK TRANSACTION
               PRINT ERROR_MESSAGE();
           END CATCH
       END
       ELSE
           PRINT('已不需折抵')
   END
   ELSE
       PRINT('錯誤/過期/使用過的優惠券!')
END


-- 繳費
DROP PROCEDURE IF EXISTS Pay
GO
CREATE PROCEDURE Pay
   @VehicleNumber NVARCHAR(8),
   @PayType bit,
   @TransactionID NVARCHAR(100) = ''
AS
BEGIN
   DECLARE @Fee INT
   DECLARE @RecordID INT
   DECLARE @ParkingLotID INT
   DECLARE @HourlyRate INT
   DECLARE @PaymentID INT
   DECLARE @FinalFee INT
   SELECT TOP 1
       @RecordID = RecordID
   FROM PARKING_RECORD
   WHERE VehicleNumber = @VehicleNumber
       AND ExitTime is NULL
   ORDER BY ExitTime DESC
   SELECT @fee = PaymentAmount, @PaymentID = PaymentID
   FROM PAYMENT_RECORD
   WHERE RecordID = @RecordID AND PaymentTime is NULL
   IF @Fee is NOT NULL
           BEGIN TRY
           BEGIN TRANSACTION
       IF @PayType = 0
       BEGIN
       UPDATE PAYMENT_RECORD SET PaymentMethod = '現金', PaymentTime = GETDATE() WHERE PaymentID = @PaymentID
       UPDATE PARKING_RECORD SET PaidUntilTime = DATEADD(MINUTE, 15, GETDATE()) WHERE RecordID = @RecordID
   END
  
       ELSE
       BEGIN
       UPDATE PAYMENT_RECORD SET PaymentMethod = '信用卡', PaymentTime = GETDATE(), TransactionID = @TransactionID WHERE PaymentID = @PaymentID
       UPDATE PARKING_RECORD SET PaidUntilTime = DATEADD(MINUTE, 15, GETDATE()) WHERE RecordID = @RecordID
   END
       COMMIT TRANSACTION
       END TRY
   BEGIN CATCH
       ROLLBACK TRANSACTION
       PRINT ERROR_MESSAGE();
       END CATCH
   ELSE
       RAISERROR('需要重金計算金額',11, 1);
END


-- 車輛離場
drop proc if EXISTS exitParkingLot
go
create proc exitParkingLot
   @LicensePlate nvarchar(8)
AS
BEGIN
   DECLARE @latestRecord int
   DECLARE @sum_fee int
   DECLARE @paidUntilTime DATETIME2


   select @latestRecord = RecordID, @paidUntilTime = paiduntiltime
   from PARKING_RECORD
   where vehiclenumber = @LicensePlate and ExitTime is NULL
   IF @paidUntilTime is NULL
   PRINT('尚未繳費，請前往繳費')
ELSE
BEGIN
       if GETDATE() < @paidUntilTime
  BEGIN
           select @sum_fee = sum(PaymentAmount)
           from payment_record
           where RecordID = @latestRecord
           GROUP BY RecordID
           -- 更新總金額和離場時間
           UPDATE PARKING_RECORD SET ExitTime = getdate(), TotalFee = @sum_fee
   where RecordID = @latestRecord
       END
 ELSE
 PRINT('已超過15分鐘，請重新繳費')
   END


END


-- 在每天固定時間刪除掉過期的折扣券, 超過24小時的紀錄也刪除
DROP PROCEDURE IF EXISTS refreshDiscount
go
CREATE PROC refreshDiscount
AS
BEGIN
   DELETE FROM discount WHERE ValidTime < GETDATE() AND PaymentID is NULL
   DELETE FROM discount WHERE ValidTime < DATEADD(HOUR, -24, GETDATE())
END
