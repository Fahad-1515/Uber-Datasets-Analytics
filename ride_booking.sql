---- I] Data Cleaning =============================================================================================================================

WITH CleanIDs AS (
    SELECT *,
        REPLACE(REPLACE([Booking ID], '"', ''), ' ', '') AS CleanBookingID,
        REPLACE(REPLACE([Customer ID], '"', ''), ' ', '') AS CleanCustomerID
    FROM dbo.ncr_ride_bookings WITH (NOLOCK)
),
CleanTextFields AS (
    SELECT *,
        TRIM([Booking Status]) AS CleanBookingStatus,
        TRIM([Vehicle Type]) AS CleanVehicleType,
        TRIM([Pickup Location]) AS CleanPickupLocation,
        TRIM([Drop Location]) AS CleanDropLocation,
        TRIM([Reason for cancelling by Customer]) AS CleanCustomerCancelReason,
        TRIM([Driver Cancellation Reason]) AS CleanDriverCancelReason,
        TRIM([Incomplete Rides Reason]) AS CleanIncompleteReason,
        TRIM([Payment Method]) AS CleanPaymentMethod
    FROM CleanIDs
),
ConvertNumerics AS (
    SELECT *,
        TRY_CAST([Date] AS DATE) AS BookingDate,
        TRY_CAST([Time] AS TIME) AS BookingTime,
        TRY_CAST([Avg VTAT] AS FLOAT) AS CleanAvgVTAT,
        TRY_CAST([Avg CTAT] AS FLOAT) AS CleanAvgCTAT,
        TRY_CAST([Cancelled Rides by Customer] AS INT) AS CleanCancelledByCustomer,
        TRY_CAST([Cancelled Rides by Driver] AS INT) AS CleanCancelledByDriver,
        TRY_CAST([Incomplete Rides] AS INT) AS CleanIncompleteRides,
        TRY_CAST([Booking Value] AS FLOAT) AS CleanBookingValue,
        TRY_CAST([Ride Distance] AS FLOAT) AS CleanRideDistance,
        TRY_CAST([Driver Ratings] AS FLOAT) AS CleanDriverRating,
        TRY_CAST([Customer Rating] AS FLOAT) AS CleanCustomerRating
    FROM CleanTextFields
),
AddTimeComponents AS (
    SELECT *,
        DATEPART(YEAR, BookingDate) AS BookingYear,
        DATEPART(MONTH, BookingDate) AS BookingMonth,
        DATEPART(QUARTER, BookingDate) AS BookingQuarter,
        DATEPART(HOUR, BookingTime) AS BookingHour,
        DATENAME(MONTH, BookingDate) AS MonthName
    FROM ConvertNumerics
),
CategorizeData AS (
    SELECT *,
        CASE 
            WHEN CleanBookingStatus = 'Completed' THEN 'Completed'
            WHEN CleanBookingStatus LIKE 'Cancelled%' THEN 'Cancelled'
            WHEN CleanBookingStatus = 'Incomplete' THEN 'Incomplete'
            WHEN CleanBookingStatus = 'No Driver Found' THEN 'NoDriver'
            ELSE 'Other'
        END AS StatusCategory,
        CASE 
            WHEN BookingMonth IN (12, 1, 2) THEN 'Winter'
            WHEN BookingMonth IN (3, 4, 5) THEN 'Spring'
            WHEN BookingMonth IN (6, 7, 8) THEN 'Summer'
            WHEN BookingMonth IN (9, 10, 11) THEN 'Fall'
        END AS Season
    FROM AddTimeComponents
),
FinalCleaning AS (
    SELECT
        CleanBookingID AS BookingID,
        CleanCustomerID AS CustomerID,
        BookingDate,
        BookingTime,
        CleanBookingStatus AS BookingStatus,
        CleanVehicleType AS VehicleType,
        CleanPickupLocation AS PickupLocation,
        CleanDropLocation AS DropLocation,
        CleanAvgVTAT AS AvgVTAT,
        CleanAvgCTAT AS AvgCTAT,
        CleanCancelledByCustomer AS CancelledByCustomer,
        CleanCustomerCancelReason AS CustomerCancelReason,
        CleanCancelledByDriver AS CancelledByDriver,
        CleanDriverCancelReason AS DriverCancelReason,
        CleanIncompleteRides AS IncompleteRides,
        CleanIncompleteReason AS IncompleteReason,
        CleanBookingValue AS BookingValue,
        CleanRideDistance AS RideDistance,
        CleanDriverRating AS DriverRating,
        CleanCustomerRating AS CustomerRating,
        CleanPaymentMethod AS PaymentMethod,
        BookingYear,
        BookingMonth,
        BookingQuarter,
        BookingHour,
        MonthName,
        StatusCategory,
        Season
    FROM CategorizeData
)
SELECT *
INTO #TempCleanedBookings
FROM FinalCleaning;

---- II] Data Analysis ==============================================================================================================================

---- Review Cleaned Data
SELECT TOP 10 *
FROM #TempCleanedBookings;

---- 1] What is the overall cancellation rate, and what is the split between driver and rider cancellations?
SELECT 
    COUNT(*) AS TotalBookings,
    SUM(CASE WHEN StatusCategory = 'Cancelled' THEN 1 ELSE 0 END) AS TotalCancellations,
    ROUND(SUM(CASE WHEN StatusCategory = 'Cancelled' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS OverallCancellationRate,
    
    SUM(CASE WHEN BookingStatus = 'Cancelled by Driver' THEN 1 ELSE 0 END) AS DriverCancellations,
    ROUND(SUM(CASE WHEN BookingStatus = 'Cancelled by Driver' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS DriverCancellationRate,
    
    SUM(CASE WHEN BookingStatus = 'Cancelled by Customer' THEN 1 ELSE 0 END) AS CustomerCancellations,
    ROUND(SUM(CASE WHEN BookingStatus = 'Cancelled by Customer' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS CustomerCancellationRate,
    
    ROUND(SUM(CASE WHEN BookingStatus = 'Cancelled by Driver' THEN 1 ELSE 0 END) * 100.0 / 
          NULLIF(SUM(CASE WHEN StatusCategory = 'Cancelled' THEN 1 ELSE 0 END), 0), 2) AS DriverShareOfCancellations,
    
    ROUND(SUM(CASE WHEN BookingStatus = 'Cancelled by Customer' THEN 1 ELSE 0 END) * 100.0 / 
          NULLIF(SUM(CASE WHEN StatusCategory = 'Cancelled' THEN 1 ELSE 0 END), 0), 2) AS CustomerShareOfCancellations
FROM #TempCleanedBookings;

---- 2] How does the cancellation rate vary by time? (Hourly analysis)
SELECT 
    BookingHour,
    COUNT(*) AS TotalBookings,
    SUM(CASE WHEN StatusCategory = 'Cancelled' THEN 1 ELSE 0 END) AS Cancellations,
    ROUND(SUM(CASE WHEN StatusCategory = 'Cancelled' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS CancellationRate,
    
    SUM(CASE WHEN BookingStatus = 'Cancelled by Driver' THEN 1 ELSE 0 END) AS DriverCancellations,
    SUM(CASE WHEN BookingStatus = 'Cancelled by Customer' THEN 1 ELSE 0 END) AS CustomerCancellations
FROM #TempCleanedBookings
GROUP BY BookingHour
ORDER BY BookingHour;

---- 3] How does the cancellation rate vary by month/season? (Seasonal trends)
SELECT 
    BookingYear,
    BookingMonth,
    MonthName,
    Season,
    COUNT(*) AS TotalBookings,
    SUM(CASE WHEN StatusCategory = 'Cancelled' THEN 1 ELSE 0 END) AS Cancellations,
    ROUND(SUM(CASE WHEN StatusCategory = 'Cancelled' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS CancellationRate,
    
    SUM(CASE WHEN BookingStatus = 'Cancelled by Driver' THEN 1 ELSE 0 END) AS DriverCancellations,
    SUM(CASE WHEN BookingStatus = 'Cancelled by Customer' THEN 1 ELSE 0 END) AS CustomerCancellations
FROM #TempCleanedBookings
GROUP BY BookingYear, BookingMonth, MonthName, Season
ORDER BY BookingYear, BookingMonth;

---- 4] Are there geographical patterns to cancellations? (By pickup location)
SELECT 
    PickupLocation,
    COUNT(*) AS TotalBookings,
    SUM(CASE WHEN StatusCategory = 'Cancelled' THEN 1 ELSE 0 END) AS Cancellations,
    ROUND(SUM(CASE WHEN StatusCategory = 'Cancelled' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS CancellationRate,
    
    SUM(CASE WHEN BookingStatus = 'Cancelled by Driver' THEN 1 ELSE 0 END) AS DriverCancellations,
    SUM(CASE WHEN BookingStatus = 'Cancelled by Customer' THEN 1 ELSE 0 END) AS CustomerCancellations,
    
    (SELECT TOP 1 COALESCE(DriverCancelReason, CustomerCancelReason)
     FROM #TempCleanedBookings t2 
     WHERE t2.PickupLocation = t1.PickupLocation 
       AND t2.StatusCategory = 'Cancelled'
       AND COALESCE(DriverCancelReason, CustomerCancelReason) IS NOT NULL
     GROUP BY COALESCE(DriverCancelReason, CustomerCancelReason)
     ORDER BY COUNT(*) DESC) AS MostCommonReason
FROM #TempCleanedBookings t1
GROUP BY PickupLocation
HAVING COUNT(*) >= 10
ORDER BY CancellationRate DESC;

---- 5] Which specific reasons are most commonly cited for cancellations?
WITH CancellationReasons AS (
    SELECT 
        COALESCE(DriverCancelReason, CustomerCancelReason) AS CancellationReason,
        CASE 
            WHEN BookingStatus = 'Cancelled by Driver' THEN 'Driver'
            WHEN BookingStatus = 'Cancelled by Customer' THEN 'Customer'
        END AS CancelledBy,
        COUNT(*) AS Count
    FROM #TempCleanedBookings
    WHERE StatusCategory = 'Cancelled'
      AND COALESCE(DriverCancelReason, CustomerCancelReason) IS NOT NULL
    GROUP BY COALESCE(DriverCancelReason, CustomerCancelReason), 
             CASE 
                 WHEN BookingStatus = 'Cancelled by Driver' THEN 'Driver'
                 WHEN BookingStatus = 'Cancelled by Customer' THEN 'Customer'
             END
)
SELECT 
    CancellationReason,
    CancelledBy,
    Count,
    ROUND(Count * 100.0 / SUM(Count) OVER(), 2) AS PercentageOfTotalCancellations
FROM CancellationReasons
ORDER BY Count DESC;

---- 6] How does cancellation rate vary by vehicle type?
SELECT 
    VehicleType,
    COUNT(*) AS TotalBookings,
    SUM(CASE WHEN StatusCategory = 'Cancelled' THEN 1 ELSE 0 END) AS Cancellations,
    ROUND(SUM(CASE WHEN StatusCategory = 'Cancelled' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS CancellationRate,
    
    SUM(CASE WHEN BookingStatus = 'Cancelled by Driver' THEN 1 ELSE 0 END) AS DriverCancellations,
    SUM(CASE WHEN BookingStatus = 'Cancelled by Customer' THEN 1 ELSE 0 END) AS CustomerCancellations,
    
    ROUND(AVG(CASE WHEN StatusCategory = 'Completed' THEN BookingValue END), 2) AS AvgCompletedValue
FROM #TempCleanedBookings
GROUP BY VehicleType
ORDER BY CancellationRate DESC;

---- Clean up temporary table
DROP TABLE #TempCleanedBookings;
