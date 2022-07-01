/*
Business rules
1. An event with a high attendance of non-cisgendered customers should have extra security detail at the event
2. Performances by Musician performers must have at least 7 security employees present
*/
USE INFO430_Proj_09
go

-- Written by: Zhan Wu

-- Stored Procedures:
-- Procedure to get ticket seller ID
CREATE PROCEDURE TicketSellerGetID
   @TicketSellerName VARCHAR(100),
   @TicketSellerCountry VARCHAR(100),
   @TicketSellerID INT OUTPUT
AS
SET @TicketSellerID = (SELECT TicketSellerID
FROM tblTICKET_SELLER
WHERE TicketSellerName = @TicketSellerName
   AND TicketSellerCountry = @TicketSellerCountry)
GO

-- Procedure to get event ID
CREATE PROCEDURE EventGetID
   @EventName VARCHAR(100),
   @BeginDate DATE,
   @EndDate DATE,
   @EventID INT OUTPUT
AS
SET @EventID = (SELECT EventID
FROM tblEVENT
WHERE EventName = @EventName
   AND BeginDate = @BeginDate
   AND EndDate = @EndDate)
GO

-- Procedure to populate event_seller table
CREATE PROCEDURE insertEVENT_SELLER
   @EventName VARCHAR(100),
   @BeginDate DATE,
   @EndDate DATE,
   @TicketSellerName VARCHAR(100),
   @TicketSellerCountry VARCHAR(100)
AS
DECLARE @TicketSellerID INT, @EventID INT

EXEC TicketSellerGetID @TicketSellerName, @TicketSellerCountry, @TicketSellerID OUTPUT
EXEC EventGetID @EventName, @BeginDate, @EndDate, @EventID OUTPUT

BEGIN TRAN G1
INSERT INTO tblEVENT_SELLER(TicketSellerID, EventID)
VALUES
   (@TicketSellerID, @EventID)
IF @@ERROR <> 0
   BEGIN
       PRINT 'There is an error occurred when insertEVENT_SELLER; time to rollback this transaction'
       ROLLBACK TRAN G1
   END
ELSE
   COMMIT TRAN G1;
GO

-- Synthetic Transaction
CREATE PROCEDURE uspEVENT_SELLER
@Run INT
AS

DECLARE @SellerCount INT = (SELECT COUNT(*) FROM tblTICKET_SELLER)
DECLARE @EventCount INT = (SELECT COUNT(*) FROM tblEVENT)

DECLARE @EName VARCHAR(100), @BDate DATE, @EDate DATE, @TSName VARCHAR(100), @TSCountry VARCHAR(50)

DECLARE @PK INT
WHILE @Run > 0
BEGIN TRAN G1
   BEGIN TRAN G2
       SET @PK = (SELECT RAND() * @SellerCount + 1)
       SET @TSName = (SELECT TicketSellerName FROM tblTICKET_SELLER WHERE TicketSellerID = @PK)
       SET @TSCountry = (SELECT TicketSellerCountry FROM tblTICKET_SELLER WHERE TicketSellerID = @PK)
       IF @TSName IS NULL AND @TSCountry IS NULL
           BEGIN
               PRINT 'There is an error occurred when get ticketSellerID; time to rollback this transaction'
               ROLLBACK TRAN G2
           END
       ELSE
           COMMIT TRAN G2
   BEGIN TRAN G3
       SET @PK = (SELECT RAND() * @EventCount + 1)
       SET @EName = (SELECT EventName FROM tblEVENT WHERE EventID = @PK)
       SET @BDate = (SELECT BeginDate FROM tblEVENT WHERE EventID = @PK)   
       SET @EDate = (SELECT EndDate FROM tblEVENT WHERE EventID = @PK)
       IF @EName IS NULL AND (@BDate IS NULL OR @EDate IS NULL)
           BEGIN
               PRINT 'There is an error occurred when get eventID; time to rollback this transaction'
               ROLLBACK TRAN G3
           END
       ELSE
           COMMIT TRAN G3
   EXEC insertEVENT_SELLER
   @EventName = @EName,
   @BeginDate = @BDate,
   @EndDate = @EDate,
   @TicketSellerName = @TSName,
   @TicketSellerCountry = @TSCountry
   SET @Run = @Run - 1

   IF @@ERROR <> 0
   BEGIN
       PRINT 'There is an error occurred when doing synthetic transaction; time to rollback this transaction'
       ROLLBACK TRAN G1
   END
   ELSE
       COMMIT TRAN G1;
GO

-- Computed Columns: 
-- 1.	 Add a column with number of VVIP and VIP in each event
CREATE FUNCTION fn_AddNumOfVVIPAndVIPInEvent(@PK INT)
RETURNS INTEGER
BEGIN
   DECLARE @RET INT = (SELECT COUNT(*) FROM tblFEE F
                       JOIN tblORDER O ON O.FeeID = F.FeeID
                       JOIN tblTICKET T ON T.OrderID = O.OrderID
                       JOIN tblEVENT_SELLER ES ON ES.EventSellerID = T.EventSellerID
                       JOIN tblEvent E ON E.EventID = ES.EventID
                       WHERE E.EventID = @PK
                       AND (F.FeeName = 'VIP' OR F.FeeName = 'VVIP'))
   RETURN @RET
END
GO

ALTER TABLE tblEvent
ADD NumOfVVIPAndVIP AS (dbo.fn_AddNumOfVVIPAndVIPInEvent(EventID))
GO

-- 2.	Add a column of percentage of 'injury' incidents of each ticketSeller which begin date is before 2010
CREATE FUNCTION fn_PctOfInjuryTicketSellerBefore2010(@PK INT)
RETURNS FLOAT(24)
BEGIN
   DECLARE @RET FLOAT(24), @INJURY FLOAT(24), @TOTAL FLOAT(24)
   SET @INJURY = (SELECT COUNT(*) FROM tblIncident_Type IT
                  JOIN tblIncident I ON I.IncidentTypeID = IT.IncidentTypeID
                  JOIN tblINCIDENT_TICKET ITK ON ITK.IncidentID = I.IncidentID
                  JOIN tblTICKET T ON T.TicketID = ITK.TicketID
                  JOIN tblEVENT_SELLER ES ON ES.EventSellerID = T.EventSellerID
                  JOIN tblTICKET_SELLER TS ON TS.TicketSellerID = ES.TicketSellerID
                  JOIN tblEvent E ON E.EventID = ES.EventID
                  WHERE IT.IncidentTypeName = 'injury'
                  AND E.Begindate < '2010-01-01'
                  AND TS.TicketSellerID = @PK)
   SET @TOTAL = (SELECT COUNT(*) FROM tblIncident_Type IT
                  JOIN tblIncident I ON I.IncidentTypeID = IT.IncidentTypeID
                  JOIN tblINCIDENT_TICKET ITK ON ITK.IncidentID = I.IncidentID
                  JOIN tblTICKET T ON T.TicketID = ITK.TicketID
                  JOIN tblEVENT_SELLER ES ON ES.EventSellerID = T.EventSellerID
                  JOIN tblTICKET_SELLER TS ON TS.TicketSellerID = ES.TicketSellerID
                  JOIN tblEvent E ON E.EventID = ES.EventID
                  WHERE E.Begindate < '2010-01-01'
                  AND TS.TicketSellerID = @PK)
   SET @RET = (@INJURY/@TOTAL)
   RETURN @RET
END
GO

ALTER TABLE tblTICKET_SELLER
ADD PctOfInjuryBefore2010 AS (dbo.fn_PctOfInjuryTicketSellerBefore2010(TicketSellerID))
GO?

-- Business Rules:
-- 1. VVIP and VIP tickets' customers have to be 21 or older. All customers must be 18 or older.
CREATE FUNCTION fn_VIPAndVVIP21OrOler()
RETURNS INTEGER
AS
BEGIN

DECLARE @RET INT = 0
IF EXISTS(SELECT C.CustFname, C.CustLname
           FROM tblCUSTOMER C
           JOIN tblORDER O ON C.CustID = O.CustID
           JOIN tblFEE F ON F.FeeID = O.FeeID
           WHERE (F.FeeName = 'VIP' OR F.FeeName = 'VVIP')
           AND DATEADD(year, 21, C.CustDOB) > GETDATE())
   BEGIN
       SET @RET = 1
   END
RETURN @RET
END
GO

ALTER TABLE tblORDER WITH NOCHECK
ADD CONSTRAINT CK_NoVVIPAndVIPUnder21
CHECK (dbo.fn_VIPAndVVIP21OrOler() = 0)
GO

-- 2. No Ticket Seller who sold ticket to customers under 18 can sell ticket for future
CREATE FUNCTION fn_NoTicketSellerSoldUnder18()
RETURNS INTEGER
AS
BEGIN

DECLARE @RET INT = 0
   IF EXISTS(SELECT TS.TicketSellerName
               FROM tblTICKET_SELLER TS
               JOIN tblEVENT_SELLER ES ON ES.TicketSellerID = TS.TicketSellerID
               JOIN tblTICKET T ON T.EventSellerID = ES.EventSellerID
               JOIN tblORDER O ON O.OrderID = T.OrderID
               JOIN tblCUSTOMER C ON C.CustID = O.CustID
               WHERE DATEADD(year, 18, C.CustDOB) > GETDATE())
       BEGIN
           SET @RET = 1
       END
RETURN @RET
END
GO

ALTER TABLE tblTICKET_SELLER WITH NOCHECK
ADD CONSTRAINT CK_NoSellerSoldTikcetsUnder18
CHECK (dbo.fn_NoTicketSellerSoldUnder18() = 0)
GO


-- Complex Views: 
1.	Create view of rank of performer and number of events
CREATE VIEW vw_NumOfEvent
AS
SELECT P.PerformerID, P.PerformerName, Count(E.EventID) AS NumOfEvent
FROM tblPERFORMER P
JOIN tblPERFORMANCE PR ON PR.PerformerID = P.PerformerID
JOIN tblEVENT E ON E.EventID = PR.EventID
GROUP BY P.PerformerID, P.PerformerName
GO

CREATE VIEW vw_NumOfTickets
AS
SELECT P.PerformerID, P.PerformerName, COUNT(T.TicketID) AS NumOfTicket
FROM tblPERFORMER P
JOIN tblPERFORMANCE PR ON P.PerformerID = PR.PerformerID
JOIN tblEvent E ON E.EventID = PR.EventID
JOIN tblEVENT_SELLER ES ON ES.EventID = E.EventID
JOIN tblTICKET T ON T.EventSellerID = ES.EventSellerID
GROUP BY P.PerformerID, P.PerformerName
GO

CREATE VIEW vw_PerformerRankAndNumOfEvent
AS
SELECT NE.PerformerID, NE.PerformerName, NE.NumOfEvent, NT.NumOfTicket, RANK() OVER(ORDER BY NT.NumOfTicket DESC) AS PerformerTicketRank
FROM vw_NumOfEvent NE
JOIN vw_NumOfTickets NT ON NE.PerformerID = NT.PerformerID
GO

SELECT * FROM vw_PerformerRankAndNumOfEvent
GO

2.	Create view of DENSE_RANK of incident type based on total incidents of each type, with another column of number of VVIP and VIP involved in each type
CREATE VIEW vw_NumOfIncidentsForEachType
AS
SELECT IT.IncidentTypeID, IT.IncidentTypeName, COUNT(I.IncidentID) AS NumOfIncidents
FROM tblIncident_Type IT
JOIN tblIncident I ON IT.IncidentTypeID = I.IncidentTypeID
GROUP BY IT.IncidentTypeID, IT.IncidentTypeName
GO

CREATE VIEW vw_NumOfVVIPAndVIPIncidentsForEachType
AS
SELECT IT.IncidentTypeID, IT.IncidentTypeName, COUNT(T.TicketID) AS NumOfVVIPAndVIPTicket
FROM tblIncident_Type IT
JOIN tblIncident I ON IT.IncidentTypeID = I.IncidentTypeID
JOIN tblINCIDENT_TICKET ITK ON I.IncidentID = ITK.IncidentID
JOIN tblTICKET T ON T.TicketID = ITK.TicketID
JOIN tblORDER O ON O.OrderID = T.OrderID
JOIN tblFEE F ON F.FeeID = O.FeeID
WHERE F.FeeName = 'VIP'
OR F.FeeName = 'VVIP'
GROUP BY IT.IncidentTypeID, IT.IncidentTypeName
GO

CREATE VIEW vw_DenseRankIncidentTypeWithVVIPAndVIPInvolved
AS
SELECT ViewOne.IncidentTypeID, ViewOne.IncidentTypeName, ISNULL(ViewTwo.NumOfVVIPAndVIPTicket,0) AS NumOfVVIPAndVIPTicket, ISNULL(ViewOne.NumOfIncidents,0) AS NumOfIncidents, DENSE_RANK() OVER(ORDER BY ISNULL(ViewOne.NumOfIncidents,0)) AS IncidentsDenseRank
FROM vw_NumOfIncidentsForEachType ViewOne
FULL OUTER JOIN vw_NumOfVVIPAndVIPIncidentsForEachType ViewTwo ON ViewOne.IncidentTypeID = ViewTwo.IncidentTypeID
GO

SELECT * FROM vw_DenseRankIncidentTypeWithVVIPAndVIPInvolved
